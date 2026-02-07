# Analysis: ORM vs Database Objects

This document clarifies which functionalities remain with Django ORM and which move to PostgreSQL database objects.

---

## SUMMARY

| Category                  | Approach              | Reason                                      |
|---------------------------|-----------------------|---------------------------------------------|
| Authentication & Sessions | Django ORM (keep)     | Django internals, tightly coupled           |
| Business CRUD Operations  | Database Objects (new)| Logic in DB required                        |
| Data Validation           | Database Objects (new)| Constraints and triggers enforce rules      |
| Aggregations & Reports    | Database Objects (new)| Views and materialized views                |
| Form Rendering & CSRF     | Django (keep)         | Presentation layer, security                |

---
### What STAYS with Django ORM:
- Login / Logout / Sessions
- Password verification
- `@login_required` decorator
- `@role_required` decorator
- Form rendering
- CSRF protection
- Django Admin (if used)
- Migrations (schema only — creates `"USER"` table)

---
### What MOVES to Database Objects:
- All CREATE operations → Stored Procedures
- All UPDATE operations → Stored Procedures
- All DELETE operations → Stored Procedures (with soft delete triggers)
- All LIST/READ operations → Views
- All aggregations/counts → Materialized Views
- All calculations → Functions
- All automatic actions → Triggers
- All validations → Triggers + CHECK constraints


## PART 1: STAYS WITH DJANGO ORM

These functionalities remain unchanged because they are Django framework internals or presentation-layer concerns.

### 1.1 Authentication System

| Functionality          | Django Component              | Why Keep ORM                              |
|------------------------|-------------------------------|-------------------------------------------|
| User login             | `authenticate()`, `login()`   | Django session backend requires ORM       |
| User logout            | `logout()`                    | Clears session via ORM                    |
| Session management     | `SessionMiddleware`           | Session table managed by Django           |
| Password verification  | `check_password()`            | Compares against ORM-fetched hash         |
| Login required check   | `@login_required`             | Reads `request.user` populated by Django  |
| Role-based access      | `@role_required`              | Reads `request.user.role` from session    |
| Password reset flow    | Django's `PasswordResetView`  | Token generation tied to ORM              |

**Files unchanged:**
- `views/auth_views.py` - `login_view()`, `logout_view()` stay as-is
- `views/decorators.py` - `@role_required` stays as-is

### 1.2 Django Admin (Optional)

| Functionality          | Why Keep ORM                                    |
|------------------------|-------------------------------------------------|
| Admin panel CRUD       | Django admin is entirely ORM-based              |
| Admin authentication   | Uses same auth system                           |

**Note:** If you don't use Django admin, this is irrelevant.

### 1.3 Form Handling (Partial)

| Functionality          | Why Keep                                        |
|------------------------|-------------------------------------------------|
| Form rendering         | HTML generation, not database logic             |
| CSRF protection        | Security middleware, not database logic         |
| Client-side validation | UX improvement, DB validates again              |
| Form field definitions | Define what fields exist, not how they're saved |

**What changes:** Forms no longer call `.save()`. Instead, cleaned data is passed to stored procedures via `connection.cursor()`.

### 1.4 Migrations (Schema Only)

| Functionality          | Why Keep                                        |
|------------------------|-------------------------------------------------|
| `makemigrations`       | Generates schema for `"USER"` table only        |
| `migrate`              | Creates `"USER"` + Django auth tables in DB     |

**Note:** Only `models.py` defines `User(AbstractUser)` with `db_table = '"USER"'`. All other tables (client, employee, warehouse, vehicle, invoice, route, delivery, etc.) are created by `DDL.sql` — not by Django migrations.

---

## PART 2: MOVES TO DATABASE OBJECTS

These functionalities move from Python/Django to PostgreSQL stored procedures, functions, triggers, and views.

> **Table/column naming convention:** All DDL.sql tables use unquoted names (lowercase in PostgreSQL catalog) except `"USER"` which is quoted. Inheritance uses **shared PK** (`child.id = parent.id`), not separate FK columns.

### 2.1 User Management

| Operation              | Old (ORM)                          | New (DB Object)           | Type      |
|------------------------|------------------------------------|---------------------------|-----------|
| Create user            | `User.objects.create_user()`       | `CALL sp_create_user()`   | Procedure |
| Update user profile    | `user.save()`                      | `CALL sp_update_user()`   | Procedure |
| Delete user            | `user.delete()`                    | `CALL sp_delete_user()`   | Procedure |
| List all clients       | `User.objects.filter(role="client")` | `SELECT * FROM v_clients` | View      |
| List potential employees | `User.objects.exclude(role__in=[...])` | `SELECT * FROM v_potential_employees` | View |

**Tables involved:** `"USER"`, `client`
**Key columns:** `"USER"`.id, username, email, password, first_name, last_name, contact, address, role, is_superuser, is_staff, is_active, last_login, created_at, updated_at · `client`.id (= `"USER"`.id), tax_id
**Role values (DDL.sql CHK_USER_ROLE):** admin, client, driver, staff, manager — **NOTE:** models.py choices list `employee` instead of `driver`/`staff`; the DDL CHECK constraint is the enforced source of truth

### 2.2 Employee Management

| Operation              | Old (ORM)                          | New (DB Object)               | Type      |
|------------------------|------------------------------------|-------------------------------|-----------|
| Create employee        | `Employee()` + `.save()` x3        | `CALL sp_create_employee()`   | Procedure |
| Update employee        | `employee.save()`                  | `CALL sp_update_employee()`   | Procedure |
| Delete employee        | `employee.delete()`                | `CALL sp_delete_employee()`   | Procedure |
| List employees         | `Employee.objects.select_related()`| `SELECT * FROM v_employees_full` | View   |
| Sync user role         | `Employee.save()` Python method    | `trg_employee_sync_user_role` | Trigger   |
| Validate license       | `EmployeeDriverForm.clean()`       | `fn_is_license_valid()`       | Function  |

**Tables involved:** `"USER"`, `employee`, `employee_driver`, `employee_staff`
**Inheritance:** `employee`.id = `"USER"`.id, `employee_driver`.id = `employee`.id, `employee_staff`.id = `employee`.id (shared PK)
**Key columns:** `employee`.war_id→warehouse, emp_position ('driver'|'staff'), schedule, wage, is_active, hire_date · `employee_driver`.license_number, license_category (A|B|C|D), license_expiry_date, driving_experience_years, driver_status · `employee_staff`.department

### 2.3 Delivery Management

| Operation              | Old (ORM)                          | New (DB Object)               | Type      |
|------------------------|------------------------------------|-------------------------------|-----------|
| Create delivery        | `Delivery.objects.create()`        | `CALL sp_create_delivery()`   | Procedure |
| Update delivery        | `delivery.save()`                  | `CALL sp_update_delivery()`   | Procedure |
| Delete delivery        | `delivery.delete()`                | `CALL sp_delete_delivery()`   | Procedure |
| List all deliveries    | `Delivery.objects.select_related()`| `SELECT * FROM v_deliveries_full` | View  |
| Client's deliveries    | `Delivery.objects.filter(client=)` | `SELECT * FROM fn_get_client_deliveries(id)` | Function |
| Driver's deliveries    | `Delivery.objects.filter(driver=)` | `SELECT * FROM fn_get_driver_deliveries(id)` | Function |
| Import from JSON       | Loop with `Delivery.objects.create()` | `CALL sp_import_deliveries(jsonb)` | Procedure |
| Export to JSON         | `Delivery.objects.all().values()`  | `SELECT * FROM v_deliveries_export` | View  |
| Export to CSV          | `export_deliveries_csv()` (exists) | Keep existing                 | Procedure |
| Status workflow        | No validation                      | `trg_delivery_status_workflow`| Trigger   |
| Timestamp validation   | Form `clean()` only                | `trg_delivery_timestamp_check`| Trigger   |
| Soft delete            | Hard delete                        | `trg_delivery_soft_delete`    | Trigger   |
| Tracking event log     | `RAISE NOTICE` only (not persistent)| `trg_delivery_tracking_log`  | Trigger   |
| Tracking timeline      | None                               | `v_delivery_tracking`         | View      |
| Tracking by number     | None                               | `fn_get_delivery_tracking(tracking_number)` | Function |
| Update delivery status | `delivery.save()` (no history)     | `CALL sp_update_delivery_status()` | Procedure |

**Tables involved:** `delivery`, `delivery_tracking`
**Key FKs:** `delivery`.driver_id→employee_driver, route_id→route, inv_id→invoice, client_id→client, war_id→warehouse
**Key columns:** tracking_number, sender_name/address/phone/email, recipient_name/address/phone/email, item_type, weight (>=1), dimensions, status, priority, in_transition, delivery_date
**Delivery statuses:** registered, ready, pending, in_transit, completed, cancelled
**Tracking:** `delivery_tracking`.del_id→delivery, staff_id→employee_staff, war_id→warehouse, status, notes, created_at (append-only event log)

### 2.4 Route Management

| Operation              | Old (ORM)                          | New (DB Object)               | Type      |
|------------------------|------------------------------------|-------------------------------|-----------|
| Create route           | `Route.objects.create()`           | `CALL sp_create_route()`      | Procedure |
| Update route           | `route.save()`                     | `CALL sp_update_route()`      | Procedure |
| Delete route           | `route.delete()`                   | `CALL sp_delete_route()`      | Procedure |
| List all routes        | `Route.objects.select_related()`   | `SELECT * FROM v_routes_full` | View      |
| Import from JSON       | Loop with `Route.objects.create()` | `CALL sp_import_routes(jsonb)`| Procedure |
| Export to JSON         | `Route.objects.all().values()`     | `SELECT * FROM v_routes_export` | View    |
| Export to CSV          | `export_routes_csv()` (exists)     | Keep existing                 | Procedure |
| Time validation        | Form `clean()` only                | `trg_route_time_check`        | Trigger   |

**Tables involved:** `route`
**Key FKs:** `route`.driver_id→employee_driver, vehicle_id→vehicle, war_id→warehouse
**Key columns:** description, delivery_status, delivery_date, delivery_start_time (TIMESTAMPTZ), delivery_end_time (TIMESTAMPTZ), expected_duration (TIME), kms_travelled, driver_notes, is_active
**Route statuses:** not_started, on_going, finished, cancelled
**Validation:** trg_route_time_check ensures delivery_end_time > delivery_start_time

### 2.5 Vehicle Management

| Operation              | Old (ORM)                          | New (DB Object)               | Type      |
|------------------------|------------------------------------|-------------------------------|-----------|
| Create vehicle         | `Vehicle.objects.create()`         | `CALL sp_create_vehicle()`    | Procedure |
| Update vehicle         | `vehicle.save()`                   | `CALL sp_update_vehicle()`    | Procedure |
| Delete vehicle         | `vehicle.delete()`                 | `CALL sp_delete_vehicle()`    | Procedure |
| List all vehicles      | `Vehicle.objects.all()`            | `SELECT * FROM v_vehicles_full` | View    |
| Import from JSON       | Loop with `Vehicle.objects.create()` | `CALL sp_import_vehicles(jsonb)` | Procedure |
| Export to JSON         | `Vehicle.objects.all().values()`   | `SELECT * FROM v_vehicles_export` | View  |
| Export to CSV          | `export_vehicles_csv()` (exists)   | Keep existing                 | Procedure |
| Year validation        | Form `clean()` only                | `fn_is_valid_year()`          | Function  |

**Tables involved:** `vehicle`
**Key columns:** vehicle_type (van|truck|motorcycle|bicycle|car), plate_number, capacity, brand, model, vehicle_status (available|in_use|maintenance|out_of_service), year, fuel_type (diesel|petrol|electric|hybrid), last_maintenance_date, is_active
**Validation:** fn_is_valid_year checks 1900 <= year <= 2100; sp_delete_vehicle blocks if active routes exist

### 2.6 Warehouse Management

| Operation              | Old (ORM)                          | New (DB Object)               | Type      |
|------------------------|------------------------------------|-------------------------------|-----------|
| Create warehouse       | `Warehouse.objects.create()`       | `CALL sp_create_warehouse()`  | Procedure |
| Update warehouse       | `warehouse.save()`                 | `CALL sp_update_warehouse()`  | Procedure |
| Delete warehouse       | `warehouse.delete()`               | `CALL sp_delete_warehouse()`  | Procedure |
| List all warehouses    | `Warehouse.objects.all()`          | `SELECT * FROM v_warehouses_full` | View  |
| Import from JSON       | Loop with `Warehouse.objects.create()` | `CALL sp_import_warehouses(jsonb)` | Procedure |
| Export to JSON         | `Warehouse.objects.all().values()` | `SELECT * FROM v_warehouses_export` | View |
| Export to CSV          | `export_warehouses_csv()` (exists) | Keep existing                 | Procedure |
| Schedule validation    | Form `clean()` only                | `trg_warehouse_schedule_check`| Trigger   |

**Tables involved:** `warehouse`
**Key columns:** name, contact, address, schedule_open (TIME), schedule_close (TIME), schedule, maximum_storage_capacity (>=1), is_active
**Validation:** trg_warehouse_schedule_check ensures schedule_close > schedule_open

### 2.7 Invoice Management

| Operation              | Old (ORM)                          | New (DB Object)               | Type      |
|------------------------|------------------------------------|-------------------------------|-----------|
| Create invoice         | `Invoice.objects.create()`         | `CALL sp_create_invoice()`    | Procedure |
| Add invoice item       | `InvoiceItem.objects.create()`     | `CALL sp_add_invoice_item()`  | Procedure |
| Update invoice         | `invoice.save()`                   | `CALL sp_update_invoice()`    | Procedure |
| Delete invoice         | `invoice.delete()`                 | `CALL sp_delete_invoice()`    | Procedure |
| List all invoices      | `Invoice.objects.prefetch_related()`| `SELECT * FROM v_invoices_with_items` | View |
| Import from JSON       | Loop with creates                  | `CALL sp_import_invoices(jsonb)` | Procedure |
| Export to JSON         | `Invoice.objects.all().values()`   | `SELECT * FROM v_invoices_export` | View  |
| Export to CSV          | `export_invoices_csv()` (exists)   | Keep existing                 | Procedure |
| Export to PDF          | Python + xhtml2pdf                 | Keep (presentation layer)     | Python    |
| Calculate item total   | `InvoiceItem.save()` Python        | `trg_invoice_item_calc_total` | Trigger   |
| Update invoice cost    | Manual in Python                   | `trg_invoice_update_cost`     | Trigger   |
| Soft delete            | Hard delete                        | `trg_invoice_soft_delete`     | Trigger   |
| Calculate subtotal     | Python loop in view                | `fn_invoice_subtotal(id)`     | Function  |
| Calculate tax          | `subtotal * 0.23` hardcoded        | `fn_calculate_tax(amt, rate)` | Function  |
| Calculate total        | Python in view                     | `fn_invoice_total(id)`        | Function  |

**Tables involved:** `invoice`, `invoice_item`
**Invoice FKs:** war_id→warehouse, staff_id→employee_staff, client_id→client
**Invoice key columns:** status (pending|completed|cancelled|refunded), type (paid_on_send|paid_on_delivery), quantity, cost, paid, pay_method (cash|card|mobile_payment|account), name, address, contact (snapshot fields)
**Invoice item key columns:** inv_id→invoice, shipment_type, weight, delivery_speed, quantity, unit_price, total_item_cost (trigger-calculated), notes
**Triggers:** trg_invoice_item_calc_total (BEFORE INSERT/UPDATE → total_item_cost = quantity * unit_price), trg_invoice_update_cost (AFTER INSERT/UPDATE/DELETE on invoice_item → recalculates invoice.cost), trg_invoice_soft_delete (BEFORE DELETE → sets status='cancelled')
**Tax rate:** 23% (configurable via fn_calculate_tax)

### 2.8 Dashboard & Aggregations

| Operation              | Old (ORM)                          | New (DB Object)               | Type           |
|------------------------|------------------------------------|-------------------------------|----------------|
| Vehicle count          | `Vehicle.objects.count()`          | `SELECT * FROM mv_dashboard_stats` | Mat. View |
| Delivery count         | `Delivery.objects.count()`         | (combined above)              | Mat. View      |
| Client count           | `User.objects.filter().count()`    | (combined above)              | Mat. View      |
| Employee count         | `Employee.objects.count()`         | (combined above)              | Mat. View      |
| Active routes count    | `Route.objects.exclude().count()`  | (combined above)              | Mat. View      |
| Pending deliveries     | `Delivery.objects.filter().count()`| (combined above)              | Mat. View      |
| Invoice count          | `Invoice.objects.count()`          | (combined above)              | Mat. View      |
| Role-specific stats    | Multiple queries in view           | `fn_get_dashboard_stats(uid, role)` | Function  |
| Invoice totals cache   | Calculated each request            | `mv_invoice_totals`           | Mat. View      |

### 2.9 Audit & Integrity

| Operation              | Old (ORM)                          | New (DB Object)               | Type      |
|------------------------|------------------------------------|-------------------------------|-----------|
| Audit trail            | None                               | `trg_audit_log`               | Trigger   |
| Soft delete delivery   | Hard delete                        | `trg_delivery_soft_delete`    | Trigger   |
| Soft delete invoice    | Hard delete                        | `trg_invoice_soft_delete`     | Trigger   |
| Status transitions     | No validation                      | `trg_delivery_status_workflow`| Trigger   |
| Tracking history       | `RAISE NOTICE` (non-persistent)    | `trg_delivery_tracking_log`   | Trigger   |

---

## PART 3: CODE CHANGE PATTERN

### Before (ORM):
```python
def deliveries_create(request):
    if request.method == "POST":
        form = DeliveryForm(request.POST)
        if form.is_valid():
            delivery = form.save()  # ORM handles everything
            return redirect("deliveries_list")
    else:
        form = DeliveryForm()
    return render(request, "deliveries/form.html", {"form": form})
```

### After (DB Objects):
```python
def deliveries_create(request):
    if request.method == "POST":
        form = DeliveryForm(request.POST)
        if form.is_valid():
            try:
                with connection.cursor() as cursor:
                    cursor.execute("CALL sp_create_delivery(%s, %s, %s, ...)", [
                        form.cleaned_data["tracking_number"],
                        form.cleaned_data["description"],
                        # ... all fields as parameters
                    ])
                return redirect("deliveries_list")
            except Exception as e:
                messages.error(request, f"Error: {e}")
    else:
        form = DeliveryForm()
    return render(request, "deliveries/form.html", {"form": form})
```

### List View - Before (ORM):
```python
def deliveries_list(request):
    deliveries = Delivery.objects.select_related("driver", "client", "route").all()
    paginator = Paginator(deliveries, 10)
    page_obj = paginator.get_page(request.GET.get("page"))
    return render(request, "deliveries/list.html", {"page_obj": page_obj})
```

### List View - After (DB Objects):
```python
def deliveries_list(request):
    with connection.cursor() as cursor:
        cursor.execute("SELECT * FROM v_deliveries_full")
        columns = [col[0] for col in cursor.description]
        deliveries = [dict(zip(columns, row)) for row in cursor.fetchall()]

    paginator = Paginator(deliveries, 10)
    page_obj = paginator.get_page(request.GET.get("page"))
    return render(request, "deliveries/list.html", {"page_obj": page_obj})
```

---

## PART 4: FILES AFFECTED

### Files That Stay Mostly Unchanged:
| File                        | Reason                                |
|-----------------------------|---------------------------------------|
| `views/auth_views.py`       | Authentication stays ORM-based        |
| `views/decorators.py`       | Role check reads from session         |
| `forms.py`                  | Form definitions stay, `.save()` removed |
| `models.py`                 | Only `User(AbstractUser)` — schema definition for `"USER"` table; `save()` methods removed |
| `templates/*`               | No changes needed                     |
| `urls.py`                   | No changes needed                     |

### Files That Need Refactoring:
| File                        | Changes Needed                        |
|-----------------------------|---------------------------------------|
| `views/deliveries.py`       | Replace ORM with cursor.execute()     |
| `views/routes.py`           | Replace ORM with cursor.execute()     |
| `views/vehicles.py`         | Replace ORM with cursor.execute()     |
| `views/warehouses.py`       | Replace ORM with cursor.execute()     |
| `views/invoices.py`         | Replace ORM with cursor.execute()     |
| `views/employees.py`        | Replace ORM with cursor.execute()     |
| `views/users.py`            | Replace ORM with cursor.execute()     |
| `views/dashboard.py`        | Replace counts with materialized view |

### New SQL Files to Create:
```
PostOffice_Proj/
└── sql/
    ├── 1_views/
    │   ├── v_delivery_tracking.sql
    │   ├── v_deliveries_full.sql
    │   ├── v_routes_full.sql
    │   ├── v_employees_full.sql
    │   ├── v_vehicles_full.sql
    │   ├── v_warehouses_full.sql
    │   ├── v_invoices_with_items.sql
    │   ├── v_clients.sql
    │   ├── v_potential_employees.sql
    │   ├── v_deliveries_export.sql
    │   ├── v_routes_export.sql
    │   ├── v_vehicles_export.sql
    │   ├── v_warehouses_export.sql
    │   └── v_invoices_export.sql
    ├── 2_functions/
    │   ├── fn_get_delivery_tracking.sql
    │   ├── fn_calculate_tax.sql
    │   ├── fn_calculate_item_total.sql
    │   ├── fn_invoice_subtotal.sql
    │   ├── fn_invoice_total.sql
    │   ├── fn_get_client_deliveries.sql
    │   ├── fn_get_driver_deliveries.sql
    │   ├── fn_get_dashboard_stats.sql
    │   ├── fn_is_license_valid.sql
    │   ├── fn_is_valid_year.sql
    │   └── fn_is_valid_status_transition.sql
    ├── 3_triggers/
    │   ├── trg_employee_sync_user_role.sql
    │   ├── trg_invoice_item_calc_total.sql
    │   ├── trg_invoice_update_cost.sql
    │   ├── trg_delivery_soft_delete.sql
    │   ├── trg_invoice_soft_delete.sql
    │   ├── trg_delivery_status_workflow.sql
    │   ├── trg_delivery_tracking_log.sql
    │   ├── trg_delivery_timestamp_check.sql
    │   ├── trg_route_time_check.sql
    │   ├── trg_warehouse_schedule_check.sql
    │   └── trg_audit_log.sql
    ├── 4_materialized_views/
    │   ├── mv_dashboard_stats.sql
    │   └── mv_invoice_totals.sql
    └── 5_procedures/
        ├── sp_create_user.sql
        ├── sp_update_user.sql
        ├── sp_delete_user.sql
        ├── sp_create_employee.sql
        ├── sp_update_employee.sql
        ├── sp_delete_employee.sql
        ├── sp_create_delivery.sql
        ├── sp_update_delivery.sql
        ├── sp_update_delivery_status.sql
        ├── sp_delete_delivery.sql
        ├── sp_import_deliveries.sql
        ├── sp_create_route.sql
        ├── sp_update_route.sql
        ├── sp_delete_route.sql
        ├── sp_import_routes.sql
        ├── sp_create_vehicle.sql
        ├── sp_update_vehicle.sql
        ├── sp_delete_vehicle.sql
        ├── sp_import_vehicles.sql
        ├── sp_create_warehouse.sql
        ├── sp_update_warehouse.sql
        ├── sp_delete_warehouse.sql
        ├── sp_import_warehouses.sql
        ├── sp_create_invoice.sql
        ├── sp_update_invoice.sql
        ├── sp_delete_invoice.sql
        ├── sp_import_invoices.sql
        └── sp_add_invoice_item.sql
```

---



### ADD LOGICAL OBJECTS WITH 1.(SAVE INTO DJANGO AND DO MIGRATE -> PGSQL) || DIRECTLY IN 2.( PGADMIN + QUERYTOOL -> PGSQL)S

# 1: SQL Files + pgAdmin

**Pros**:
- Files are version controlled and submitted with project
- Professor can see all your SQL code organized
- Run manually in pgAdmin during development
- Quick to test and iterate

**Cons**:
- Manual process to apply changes
- If DB is dropped, must re-run everything manually


# 2: Django Migrations with RunSQL

# migrations/0002_create_db_objects.py
from django.db import migrations

class Migration(migrations.Migration):
    dependencies = [('PostOffice_App', '0001_initial')]

    operations = [
        migrations.RunSQL(
            sql=open('sql/views/v_employees_full.sql').read(),
            reverse_sql="DROP VIEW IF EXISTS v_employees_full;"
        ),
        migrations.RunSQL(
            sql=open('sql/procedures/sp_create_employee.sql').read(),
            reverse_sql="DROP PROCEDURE IF EXISTS sp_create_employee;"
        ),
        # ... more
    ]

**Pros**:
- python manage.py migrate creates everything automatically
- Reproducible on any machine
- Professional approach

**Cons**:
- More setup work
- Harder to iterate quickly during development


Recommendation for a Course Project:
    Use both:

┌──────────────────┬──────────────────────────────────────────────┐
│      Phase       │                   Approach                   │
├──────────────────┼──────────────────────────────────────────────┤
│ Development      │ SQL files in sql/ folder → run in pgAdmin    │
├──────────────────┼──────────────────────────────────────────────┤
│ Final submission │ Add Django migration that runs the SQL files │

└──────────────────┴──────────────────────────────────────────────┘


Why **numbered folders**? **Order matters** - functions must exist before procedures that call them, views before materialized views that reference them, etc.
