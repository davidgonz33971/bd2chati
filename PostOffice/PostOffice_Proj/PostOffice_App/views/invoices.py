# ==========================================================
#  INVOICES
# ==========================================================
from datetime import datetime
from decimal import Decimal
import json
from pyexpat.errors import messages
from django.db import connection
from django.shortcuts import render, get_object_or_404, redirect
from django.http import HttpResponse, HttpResponseBadRequest, JsonResponse
from ..models import Invoice, User
from ..forms import InvoiceForm
from .decorators import role_required
from django.contrib.auth.decorators import login_required
from django.core.paginator import Paginator

from ..notifications import create_notification

@login_required
@role_required(["admin", "client"])
def invoice_list(request):
    """List all invoices (admin sees all, clients see only their own)"""
    if request.user.role == "client":
        invoices_qs = Invoice.objects.filter(user=request.user).order_by("-invoice_datetime")
    else:
        invoices_qs = Invoice.objects.select_related("user").all().order_by("-invoice_datetime")

    paginator = Paginator(invoices_qs, 10)
    page_number = request.GET.get("page")
    invoices_page = paginator.get_page(page_number)

    return render(request, "invoices/list.html", {"invoices": invoices_page})


@login_required
@role_required(["admin"])
def invoice_create(request):
    """Create a new invoice"""
    if request.method == "POST":
        form = InvoiceForm(request.POST)
        if form.is_valid():
            # Save the invoice and get the instance
            invoice_obj = form.save()

            # Notification for the client (if they have contact/email)
            if invoice_obj.user and invoice_obj.user.email:
                create_notification(
                    notification_type="invoice_created",
                    recipient_contact=invoice_obj.user.email,
                    subject="New Invoice",
                    message=f"Invoice #{invoice_obj.id_invoice} has been created for €{invoice_obj.cost}.",
                )

            # Notification for the admin who created it
            create_notification(
                notification_type="invoice_created_admin",
                recipient_contact=request.user.email,
                subject="Invoice Created",
                message=f" Successfully created invoice #{invoice_obj.id_invoice} (€{invoice_obj.cost})",
                status="sent"
            )

            return redirect("invoice_list")
    else:
        form = InvoiceForm()

    return render(request, "invoices/create.html", {"form": form})


@login_required
@role_required(["admin"])
def invoice_edit(request, invoice_id):
    """Edit an existing invoice"""
    invoice = get_object_or_404(Invoice, pk=invoice_id)

    if request.method == "POST":
        form = InvoiceForm(request.POST, instance=invoice)
        if form.is_valid():
            # Save the updated invoice
            invoice_obj = form.save()

            # Notification for the client (if they have contact/email)
            if invoice_obj.user and invoice_obj.user.email:
                create_notification(
                    notification_type="invoice_updated",
                    recipient_contact=invoice_obj.user.email,
                    subject="Invoice Updated",
                    message=f"Invoice #{invoice_obj.id_invoice} has been updated.",
                )

            # Notification for the admin who edited it
            create_notification(
                notification_type="invoice_updated_admin",
                recipient_contact=request.user.email,
                subject="Invoice Updated",
                message=f"Successfully updated invoice #{invoice_obj.id_invoice} (€{invoice_obj.cost})",
                status="sent"
            )

            return redirect("invoice_list")
    else:
        form = InvoiceForm(instance=invoice)

    return render(request, "invoices/edit.html", {"form": form, "invoice": invoice})


@login_required
@role_required(["admin"])
def invoice_delete(request, invoice_id):
    """Delete an invoice"""
    if request.method != "POST":
        return HttpResponseBadRequest("Invalid request method for deletion.")

    invoice = get_object_or_404(Invoice, pk=invoice_id)
    # Store invoice info before deleting
    invoice_info = f"#{invoice.id_invoice} (€{invoice.cost})"

    try:
        invoice.delete()

        # Create notification after successful deletion
        create_notification(
            notification_type="invoice_deleted",
            recipient_contact=request.user.email,
            subject="Invoice Deleted",
            message=f"Successfully deleted invoice {invoice_info}",
            status="sent"
        )

        messages.success(request, "Invoice deleted successfully.")
    except Exception:
        messages.error(request, "An error occurred while deleting the invoice.")

    return redirect("invoice_list")


# ==========================================================
# IMPORT/EXPORT JSON
# ==========================================================

def invoices_import_json(request):
    if request.method == "POST":
        file = request.FILES.get("file")
        if not file:
            messages.error(request, "No file uploaded.")
            return redirect("invoices_import_json")

        try:
            data = json.load(file)
        except Exception:
            messages.error(request, "Invalid JSON.")
            return redirect("invoices_import_json")

        for item in data:
            inv = Invoice(
                id_invoice=item.get("id_invoice"),
                invoice_status=item.get("invoice_status",""),
                invoice_type=item.get("invoice_type",""),
                quantity=item.get("quantity"),
                invoice_datetime=item.get("invoice_datetime"),
                cost=item.get("cost"),
                paid=item.get("paid",False),
                payment_method=item.get("payment_method",""),
                name=item.get("name",""),
                address=item.get("address",""),
                contact=item.get("contact","")
            )

            user_id = item.get("user_id")
            if user_id:
                try:
                    inv.user = User.objects.get(id=user_id)
                except User.DoesNotExist:
                    pass

            inv.save()

        messages.success(request, "Invoices imported successfully.")
        return redirect("invoice_list")

    return render(request, "invoices/import.html")

@login_required
@role_required(["admin", "manager"])
def invoices_export_json(request):
    """Export all invoices to JSON"""
    invoices = list(
        Invoice.objects.all().values(
            "id_invoice",
            "invoice_datetime",
            "invoice_status",
            "invoice_type",
            "cost",
            "payment_method",
            "address",
            "contact",
            "quantity",
            "name",
            "paid",
            "user_id",
        )
    )

    for inv in invoices:
        dt = inv.get("invoice_datetime")
        if isinstance(dt, datetime):
            inv["invoice_datetime"] = dt.strftime("%Y-%m-%d %H:%M:%S")

        cost = inv.get("cost")
        if isinstance(cost, Decimal):
            inv["cost"] = float(cost)

        qty = inv.get("quantity")
        if isinstance(qty, Decimal):
            inv["quantity"] = float(qty)

    json_data = json.dumps(invoices, indent=4)
    response = HttpResponse(json_data, content_type="application/json")
    response["Content-Disposition"] = 'attachment; filename="invoices_export.json"'

    # Create notification for the user who exported
    create_notification(
        notification_type="invoices_exported",
        recipient_contact=request.user.email,
        subject="Invoices Exported",
        message=f"Successfully exported {len(invoices)} invoices to JSON",
        status="sent"
    )

    return response


# ==================== Export csv ====================
@login_required
@role_required(["admin", "manager"])
def invoices_export_csv(request):
    """Export all invoices to CSV using PostgreSQL function"""
    with connection.cursor() as cursor:
        cursor.execute("SELECT * FROM export_invoices_csv();")
        rows = cursor.fetchall()

    header = (
        "id_invoice,invoice_status,invoice_type,quantity,"
        "invoice_datetime,cost,paid,payment_method,"
        "name,address,contact,user_id\n"
    )
    csv_data = header + "\n".join(r[0] for r in rows)

    response = HttpResponse(csv_data, content_type="text/csv")
    response["Content-Disposition"] = 'attachment; filename="invoices_export.csv"'

    # Create notification for the user who exported
    create_notification(
        notification_type="invoices_exported_csv",
        recipient_contact=request.user.email,
        subject="Invoices Exported",
        message=f"Successfully exported {len(rows)} invoices to CSV",
        status="sent"
    )

    return response