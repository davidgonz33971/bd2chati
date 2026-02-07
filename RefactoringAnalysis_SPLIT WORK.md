# CREATING THE BD:
1. Run Django migrations first (enable django login handling)
    * Django migrations create identity(USERS) tables only -> minimal models.py
    python manage.py makemigrations PostOffice_App
    py manage.py migrate
2. Run the DDL.sql in pgadmin QueryTool:
    * Create all the data infrastructure


# Refactoring Analysis: Django ORM to Database Objects

This document maps all current Django ORM operations to their appropriate PostgreSQL database objects (Views, Materialized Views, Triggers, Functions, Procedures).


## SUMMARY of all OBJECTS to implement

### By Database Object:
| Type                   | Count | Objects                                          |
|------------------------|-------|--------------------------------------------------|
| **VIEWS**              | 14    | List views, filtered views, export views, tracking |
| **MATERIALIZED VIEWS** | 2     | Dashboard stats, invoice totals                  |
| **TRIGGER FUNCTIONS**  | 11    | Role sync, calculations, soft delete, audit, val., tracking |
| **FUNCTIONS**          | 11    | Tax calc, totals, queries, validation, tracking  |
| **PROCEDURES**         | 26+   | All CRUD operations + bulk imports + status update |

### By Entity:
| Entity         | Views | Mat.Views | Triggers | Functions | Procedures             |
|----------------|-------|-----------|----------|-----------|------------------------|
| User           | 2     | -         | -        | -         | 3                      | 5   DIEGO
| Employee       | 1     | -         | 1        | -         | 3                      | 5
| EmployeeDriver | -     | -         | -        | 1         | (in sp_create_employee)| 2
| EmployeeStaff  | -     | -         | -        | -         | (in sp_create_employee)| 1
| Warehouse      | 2     | -         | 1        | -         | 4                      | 7 ___
| Delivery       | 2     | -         | 3        | 3         | 5                      | 13 DAVID
| DeliveryTracking| 1    | -         | 1        | 1         | -                      | 3 ___
| Invoice        | 2     | 1         | 1        | 3         | 4                      | 11
| InvoiceItem    | -     | -         | 2        | 1         | 1                      | 4
| Dashboard      | -     | 1         | -        | 1         | -                      | 3  ROD
| Vehicle        | 2     | -         | -        | 1         | 4                      | 7
| Route          | 2     | -         | 1        | -         | 4                      | 7

| Entity         | Views | Mat.Views | Triggers | Functions | Procedures             |
|----------------|-------|-----------|----------|-----------|------------------------|
| User           | 2     | -         | -        | -         | 3                      | 5
| Employee       | 1     | -         | 1        | -         | 3                      | 5
| EmployeeDriver | -     | -         | -        | 1         | (in sp_create_employee)| 2
| EmployeeStaff  | -     | -         | -        | -         | (in sp_create_employee)| 1
| Warehouse      | 2     | -         | 1        | -         | 4                      | 7
| Delivery       | 2     | -         | 3        | 3         | 5                      | 13
| DeliveryTracking| 1    | -         | 1        | 1         | -                      | 3
| Invoice        | 2     | 1         | 1        | 3         | 4                      | 11
| InvoiceItem    | -     | -         | 2        | 1         | 1                      | 4
| Dashboard      | -     | 1         | -        | 1         | -                      | 3
| Vehicle        | 2     | -         | -        | 1         | 4                      | 7
| Route          | 2     | -         | 1        | -         | 4                      | 7

---


## EXISTING PROCEDURES TO KEEP
These already exist and are called via `connection.cursor()`:

| Procedure                | File Reference     | Keep/Modify |
|--------------------------|--------------------|-------------|
| `export_deliveries_csv()`| deliveries.py:250  | Keep        |
| `export_routes_csv()`    | routes.py:247      | Keep        |
| `export_vehicles_csv()`  | vehicles.py:211    | Keep        |
| `export_warehouses_csv()`| warehouses.py:260  | Keep        |
| `export_invoices_csv()`  | invoices.py:275    | Keep        |

---


## WHAT DOES EACH TYPE OF DATABASE OBJECT :

| Object Type            | Use Case                              | Characteristics                                      |
|------------------------|---------------------------------------|------------------------------------------------------|
| **VIEW**               | Read-only queries with joins/filters  | Real-time data, no caching, SELECT only              |
| **MATERIALIZED VIEW**  | Expensive aggregations, dashboard stats | Cached, requires REFRESH, read-heavy                |
| **TRIGGER FUNCTION**   | Automatic actions on data changes     | Fires on INSERT/UPDATE/DELETE, enforces rules        |
| **FUNCTION**           | Reusable calculations, returns values | Called explicitly, returns scalar/table              |
| **PROCEDURE**          | CRUD operations with business logic   | Called explicitly, can modify data, transaction ctrl |

---



## Implementation Example

## IMPLEMENTATION EXAMPLE: Employee CRUD

This example demonstrates the full refactoring pattern for **Employee management**, showing the current Django ORM approach vs. the new database objects approach.

### Current Schema (DDL.sql — shared-PK inheritance)

```
"USER" (Django-managed, AbstractUser + contact, address, role, updated_at)
  ├── CLIENT (shared PK → "USER".id)  ─── has tax_id
  └── EMPLOYEE (shared PK → "USER".id) ── has war_id, emp_position, schedule, wage, ...
        ├── EMPLOYEE_DRIVER (shared PK → EMPLOYEE.id) ── license_number, license_category, ...
        └── EMPLOYEE_STAFF  (shared PK → EMPLOYEE.id) ── department
```

**Key:** Every child table's `id` column IS the parent table's `id` — no separate `user_id` or `employee_id` FK columns.

### Current Implementation (Django ORM — OLD, being replaced)

**models.py** - Employee model with role sync in Python:
```python
class Employee(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="employee")
    position = models.CharField(max_length=50, choices=[("Driver", "Driver"), ("Staff", "Staff")])
    schedule = models.CharField(max_length=50)
    wage = models.DecimalField(max_digits=8, decimal_places=2, default=0.00)
    is_active = models.BooleanField(default=True)
    hire_date = models.DateField(null=True, blank=True)

    def save(self, *args, **kwargs):
        # PROBLEM: Role sync happens in Python, not atomic with employee save
        if self.user_id:
            if self.position == "Driver":
                self.user.role = "driver"
            elif self.position == "Staff":
                self.user.role = "staff"
            self.user.save(update_fields=["role"])
        super().save(*args, **kwargs)
```

**views/employees.py** - Create employee with ORM:
```python
@login_required
@role_required(["admin", "manager"])
def employees_create(request):
    if request.method == "POST":
        user_form = UserForm(request.POST)
        emp_form = EmployeeForm(request.POST)
        driver_form = EmployeeDriverForm(request.POST)
        staff_form = EmployeeStaffForm(request.POST)

        if user_form.is_valid() and emp_form.is_valid():
            # Multiple separate saves - not transactional!
            user = user_form.save(commit=False)
            user.set_password(user_form.cleaned_data["password"])
            user.save()  # Save 1

            employee = emp_form.save(commit=False)
            employee.user = user
            employee.save()  # Save 2 (triggers role sync)

            if employee.position == "Driver" and driver_form.is_valid():
                driver = driver_form.save(commit=False)
                driver.employee = employee
                driver.save()  # Save 3

            return redirect("employees_list")
```

### New Implementation (Database Objects)

#### A. Trigger Function - Auto-sync user role

```sql
-- Trigger: trg_employee_sync_user_role
-- Fires: AFTER INSERT OR UPDATE OF emp_position ON employee
-- Tables: employee → "USER" (shared-PK link via employee.id = "USER".id)

CREATE OR REPLACE FUNCTION fn_sync_employee_user_role()
RETURNS TRIGGER AS $$
BEGIN
    -- Automatically update user role when employee position changes
    IF NEW.emp_position = 'driver' THEN
        UPDATE "USER"
        SET role = 'driver', updated_at = NOW()
        WHERE id = NEW.id;
    ELSIF NEW.emp_position = 'staff' THEN
        UPDATE "USER"
        SET role = 'staff', updated_at = NOW()
        WHERE id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS trg_employee_sync_user_role ON employee;
CREATE TRIGGER trg_employee_sync_user_role
    AFTER INSERT OR UPDATE OF emp_position ON employee
    FOR EACH ROW
    EXECUTE FUNCTION fn_sync_employee_user_role();
```

#### B. Stored Procedure - Create Employee (with driver/staff info)

```sql
-- Procedure: sp_create_employee
-- Tables: "USER", employee, employee_driver, employee_staff
-- Inheritance: shared-PK (employee.id = "USER".id, employee_driver.id = employee.id)

CREATE OR REPLACE PROCEDURE sp_create_employee(
    -- User params (inserted into "USER")
    p_username VARCHAR(150),
    p_email VARCHAR(254),
    p_password VARCHAR(128),       -- Already hashed by Django (make_password)
    p_first_name VARCHAR(150),
    p_last_name VARCHAR(150),
    p_contact VARCHAR(20),
    p_address VARCHAR(255),
    -- Employee params (inserted into employee)
    p_war_id INT,                  -- FK → warehouse.id
    p_emp_position VARCHAR(32),    -- 'driver' | 'staff'
    p_schedule VARCHAR(255),
    p_wage DECIMAL(10,2),
    p_hire_date DATE,
    -- Driver params (nullable — only used when emp_position = 'driver')
    p_license_number VARCHAR(50) DEFAULT NULL,
    p_license_category VARCHAR(20) DEFAULT NULL,
    p_license_expiry DATE DEFAULT NULL,
    p_driving_experience INT DEFAULT NULL,
    p_driver_status VARCHAR(20) DEFAULT NULL,
    -- Staff params (nullable — only used when emp_position = 'staff')
    p_department VARCHAR(32) DEFAULT NULL,
    -- Output
    INOUT o_user_id INT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Validate position
    IF p_emp_position NOT IN ('driver', 'staff') THEN
        RAISE EXCEPTION 'Invalid position: %. Must be driver or staff', p_emp_position;
    END IF;

    -- Validate driver has required fields
    IF p_emp_position = 'driver' AND (p_license_number IS NULL OR p_license_expiry IS NULL) THEN
        RAISE EXCEPTION 'Driver position requires license_number and license_expiry';
    END IF;

    -- Validate license not expired
    IF p_emp_position = 'driver' AND p_license_expiry <= CURRENT_DATE THEN
        RAISE EXCEPTION 'License expiry date must be in the future';
    END IF;

    -- Validate staff has department
    IF p_emp_position = 'staff' AND p_department IS NULL THEN
        RAISE EXCEPTION 'Staff position requires department';
    END IF;

    -- Validate wage
    IF p_wage < 0 THEN
        RAISE EXCEPTION 'Wage cannot be negative';
    END IF;

    -- 1) Create user in "USER" (role set temporarily; trigger will sync after employee insert)
    INSERT INTO "USER" (
        username, email, password, first_name, last_name,
        contact, address, role,
        is_superuser, is_staff, is_active, created_at, updated_at
    ) VALUES (
        p_username, p_email, p_password, p_first_name, p_last_name,
        p_contact, p_address, 'client',    -- temp role; trigger fixes it
        FALSE, FALSE, TRUE, NOW(), NOW()
    ) RETURNING id INTO o_user_id;

    -- 2) Create employee (shared PK = same id as "USER")
    --    This fires trg_employee_sync_user_role → updates "USER".role
    INSERT INTO employee (
        id, war_id, emp_position, schedule, wage, is_active, hire_date
    ) VALUES (
        o_user_id, p_war_id, p_emp_position, p_schedule, p_wage, TRUE, p_hire_date
    );

    -- 3) Create driver-specific record (shared PK = same id as employee)
    IF p_emp_position = 'driver' THEN
        INSERT INTO employee_driver (
            id, license_number, license_category,
            license_expiry_date, driving_experience_years, driver_status
        ) VALUES (
            o_user_id, p_license_number, p_license_category,
            p_license_expiry, p_driving_experience, p_driver_status
        );
    END IF;

    -- 4) Create staff-specific record (shared PK = same id as employee)
    IF p_emp_position = 'staff' THEN
        INSERT INTO employee_staff (
            id, department
        ) VALUES (
            o_user_id, p_department
        );
    END IF;
END;
$$;
```

#### C. View - Employees list with user info

```sql
-- View: v_employees_full
-- Joins: employee → "USER" (shared PK), employee_driver, employee_staff
-- All joins on id = id (shared-PK inheritance)

CREATE OR REPLACE VIEW v_employees_full AS
SELECT
    e.id,
    e.emp_position,
    e.schedule,
    e.wage,
    e.is_active,
    e.hire_date,
    e.war_id,
    u.username,
    u.email,
    u.first_name,
    u.last_name,
    u.first_name || ' ' || u.last_name AS full_name,
    u.contact,
    u.address,
    u.role,
    -- Driver info (NULL if not driver)
    ed.license_number,
    ed.license_category,
    ed.license_expiry_date,
    ed.driving_experience_years,
    ed.driver_status,
    -- Staff info (NULL if not staff)
    es.department
FROM employee e
JOIN "USER" u              ON u.id  = e.id      -- shared PK
LEFT JOIN employee_driver ed ON ed.id = e.id     -- shared PK
LEFT JOIN employee_staff es  ON es.id = e.id     -- shared PK
WHERE e.is_active = TRUE
ORDER BY u.first_name, u.last_name;
```

#### D. Updated Django View - Using raw SQL

```python
# views/employees.py - Refactored to use database objects

from django.db import connection
from django.contrib.auth.hashers import make_password

@login_required
@role_required(["admin", "manager"])
def employees_list(request):
    """List employees using database view instead of ORM."""
    with connection.cursor() as cursor:
        cursor.execute("SELECT * FROM v_employees_full")
        columns = [col[0] for col in cursor.description]
        employees = [dict(zip(columns, row)) for row in cursor.fetchall()]

    # Pagination
    paginator = Paginator(employees, 10)
    page_number = request.GET.get("page")
    page_obj = paginator.get_page(page_number)

    return render(request, "employees/employees_list.html", {"page_obj": page_obj})


@login_required
@role_required(["admin", "manager"])
def employees_create(request):
    """Create employee using stored procedure instead of ORM."""
    if request.method == "POST":
        # Collect form data (still use Django forms for validation/CSRF)
        user_form = UserForm(request.POST)
        emp_form = EmployeeForm(request.POST)
        driver_form = EmployeeDriverForm(request.POST)
        staff_form = EmployeeStaffForm(request.POST)

        position = request.POST.get("emp_position")
        forms_valid = user_form.is_valid() and emp_form.is_valid()

        if position == "driver":
            forms_valid = forms_valid and driver_form.is_valid()
        elif position == "staff":
            forms_valid = forms_valid and staff_form.is_valid()

        if forms_valid:
            try:
                # Hash password in Python (Django's hasher)
                hashed_password = make_password(user_form.cleaned_data["password"])

                # Call stored procedure - single atomic transaction
                with connection.cursor() as cursor:
                    cursor.execute("""
                        CALL sp_create_employee(
                            %s, %s, %s, %s, %s, %s, %s,     -- user params
                            %s, %s, %s, %s, %s,              -- employee params
                            %s, %s, %s, %s, %s,              -- driver params
                            %s,                               -- staff params
                            NULL                              -- INOUT o_user_id
                        )
                    """, [
                        # User params → "USER" table
                        user_form.cleaned_data["username"],
                        user_form.cleaned_data["email"],
                        hashed_password,
                        user_form.cleaned_data["first_name"],
                        user_form.cleaned_data["last_name"],
                        user_form.cleaned_data["contact"],
                        user_form.cleaned_data["address"],
                        # Employee params → employee table
                        emp_form.cleaned_data.get("war_id"),
                        emp_form.cleaned_data["emp_position"],
                        emp_form.cleaned_data["schedule"],
                        emp_form.cleaned_data["wage"],
                        emp_form.cleaned_data.get("hire_date"),
                        # Driver params → employee_driver table (None if not driver)
                        driver_form.cleaned_data.get("license_number") if position == "driver" else None,
                        driver_form.cleaned_data.get("license_category") if position == "driver" else None,
                        driver_form.cleaned_data.get("license_expiry_date") if position == "driver" else None,
                        driver_form.cleaned_data.get("driving_experience_years") if position == "driver" else None,
                        driver_form.cleaned_data.get("driver_status") if position == "driver" else None,
                        # Staff params → employee_staff table (None if not staff)
                        staff_form.cleaned_data.get("department") if position == "staff" else None,
                    ])

                messages.success(request, "Employee created successfully.")
                return redirect("employees_list")

            except Exception as e:
                # Database-level validation errors surface here
                messages.error(request, f"Database error: {str(e)}")
    else:
        user_form = UserForm()
        emp_form = EmployeeForm()
        driver_form = EmployeeDriverForm()
        staff_form = EmployeeStaffForm()

    return render(request, "employees/employees_form.html", {
        "user_form": user_form,
        "emp_form": emp_form,
        "driver_form": driver_form,
        "staff_form": staff_form,
    })
```

### Key Differences Summary

| Aspect                     | Before (ORM)                          | After (DB Objects)                       |
|----------------------------|---------------------------------------|------------------------------------------|
| **Role sync**              | Python `save()` method, not atomic    | Trigger fires automatically, same txn    |
| **Validation**             | Python forms + model `clean()`        | Database constraints + procedure RAISE   |
| **Transaction**            | Multiple `.save()` calls, can fail    | Single `CALL` - all or nothing           |
| **Data access**            | `Employee.objects.select_related()`   | `SELECT * FROM v_employees_full`         |
| **Business logic location**| Scattered in models.py + views.py     | Centralized in database                  |
| **Error handling**         | Python exceptions                     | PostgreSQL exceptions → Python           |
| **Inheritance model**      | Django OneToOneField (separate IDs)   | Shared-PK inheritance (same id)          |
| **Table names**            | `postoffice_app_employee` (auto)      | `employee` (DDL.sql, unquoted lowercase) |

### Files to Create for Full Employee Refactoring

```
PostOffice_Proj/
├── migrations/
│   └── sql/
│       ├── views/
│       │   └── v_employees_full.sql
│       ├── triggers/
│       │   └── trg_employee_sync_user_role.sql
│       ├── procedures/
│       │   ├── sp_create_employee.sql
│       │   ├── sp_update_employee.sql
│       │   └── sp_delete_employee.sql
│       └── functions/
│           └── fn_is_license_valid.sql
```

---

## MIGRATION STRATEGY

### Phase 1: Create Database Objects (No Code Changes)
1. Create all VIEWs
2. Create all MATERIALIZED VIEWs
3. Create all FUNCTIONs
4. Create all TRIGGERs
5. Create all PROCEDUREs
6. Test each in isolation with psql

### Phase 2: Refactor Read Operations
1. Replace `Model.objects.all()` with VIEW queries
2. Replace `Model.objects.filter()` with parameterized VIEW queries or FUNCTIONs
3. Replace aggregations with MATERIALIZED VIEW queries
4. Keep Django models for migrations/admin

### Phase 3: Refactor Write Operations
1. Replace `Model.objects.create()` with PROCEDURE calls
2. Replace `.save()` with UPDATE procedures
3. Replace `.delete()` with soft-delete procedures
4. Remove business logic from Python `save()` methods

### Phase 4: Cleanup
1. Remove redundant model methods
2. Remove form validation duplicated by DB constraints
3. Update tests to verify database-level behavior
4. Document all database objects

---

## CHECKLIST

### Views to Create
- [ ] `v_delivery_tracking`
- [ ] `v_deliveries_full`
- [ ] `v_routes_full`
- [ ] `v_employees_full`
- [ ] `v_invoices_with_items`
- [ ] `v_vehicles_full`
- [ ] `v_warehouses_full`
- [ ] `v_clients`
- [ ] `v_potential_employees`
- [ ] `v_deliveries_export`
- [ ] `v_routes_export`
- [ ] `v_vehicles_export`
- [ ] `v_warehouses_export`
- [ ] `v_invoices_export`

### Materialized Views to Create
- [ ] `mv_dashboard_stats`
- [ ] `mv_invoice_totals`

### Trigger Functions to Create
- [ ] `trg_employee_sync_user_role`
- [ ] `trg_invoice_item_calc_total`
- [ ] `trg_invoice_update_cost`
- [ ] `trg_delivery_soft_delete`
- [ ] `trg_invoice_soft_delete`
- [ ] `trg_delivery_status_workflow`
- [ ] `trg_delivery_tracking_log`
- [ ] `trg_delivery_timestamp_check`
- [ ] `trg_route_time_check`
- [ ] `trg_warehouse_schedule_check`
- [ ] `trg_audit_log`

### Functions to Create
- [ ] `fn_calculate_tax(amount, rate)`
- [ ] `fn_calculate_item_total(qty, price)`
- [ ] `fn_invoice_subtotal(invoice_id)`
- [ ] `fn_invoice_total(invoice_id)`
- [ ] `fn_get_client_deliveries(client_id)`
- [ ] `fn_get_driver_deliveries(driver_id)`
- [ ] `fn_get_delivery_tracking(tracking_number)`
- [ ] `fn_get_dashboard_stats(user_id, role)`
- [ ] `fn_is_license_valid(expiry_date)`
- [ ] `fn_is_valid_year(year)`
- [ ] `fn_is_valid_status_transition(old, new)`

### Procedures to Create
- [ ] `sp_create_user` / `sp_update_user` / `sp_delete_user`
- [ ] `sp_create_employee` / `sp_update_employee` / `sp_delete_employee`
- [ ] `sp_create_delivery` / `sp_update_delivery` / `sp_update_delivery_status` / `sp_delete_delivery` / `sp_import_deliveries`
- [ ] `sp_create_route` / `sp_update_route` / `sp_delete_route` / `sp_import_routes`
- [ ] `sp_create_vehicle` / `sp_update_vehicle` / `sp_delete_vehicle` / `sp_import_vehicles`
- [ ] `sp_create_warehouse` / `sp_update_warehouse` / `sp_delete_warehouse` / `sp_import_warehouses`
- [ ] `sp_create_invoice` / `sp_update_invoice` / `sp_delete_invoice` / `sp_import_invoices`
- [ ] `sp_add_invoice_item`

---

## TABLE REFERENCE (DDL.sql — actual column names)

> All table/column names are **unquoted lowercase** in PostgreSQL except `"USER"` which is quoted.
> Inheritance uses **shared PK** (`child.id = parent.id`), not separate FK columns.

| Table | PK | Key Columns | CHECK Constraints |
|-------|-----|-------------|-------------------|
| `"USER"` (Django) | id SERIAL | username, email, password, first_name, last_name, contact, address, role, is_superuser, is_staff, is_active, last_login, created_at, updated_at | `CHK_USER_ROLE`: admin, client, driver, staff, manager (**NOTE:** models.py choices list `employee` instead of `driver`/`staff` — DDL.sql CHECK constraint is the enforced source of truth) |
| `client` | id INT4 (= USER.id) | tax_id | — |
| `employee` | id INT4 (= USER.id) | war_id→warehouse, emp_position, schedule, wage, is_active, hire_date | `CHK_EMPLOYEE_POSITION`: driver, staff |
| `employee_driver` | id INT4 (= employee.id) | license_number, license_category, license_expiry_date, driving_experience_years, driver_status | `CHK_DRIVER_LICENSE_CAT`: A,B,C,D · `CHK_DRIVER_STATUS`: available, on_duty, off_duty, on_break |
| `employee_staff` | id INT4 (= employee.id) | department | `CHK_STAFF_DEPARTMENT`: customer_service, sorting, administration |
| `warehouse` | id SERIAL | name, contact, address, schedule_open, schedule_close, schedule, maximum_storage_capacity, is_active, created_at, updated_at | `CHK_WAREHOUSE_CAPACITY`: >= 1 |
| `vehicle` | id SERIAL | vehicle_type, plate_number, capacity, brand, model, vehicle_status, year, fuel_type, last_maintenance_date, is_active, created_at, updated_at | `CHK_VEHICLE_TYPE`: van,truck,motorcycle,bicycle,car · `CHK_VEHICLE_STATUS`: available,in_use,maintenance,out_of_service · `CHK_VEHICLE_FUEL`: diesel,petrol,electric,hybrid |
| `invoice` | id SERIAL | war_id→warehouse, staff_id→employee_staff, client_id→client, status, type, quantity, cost, paid, pay_method, name, address, contact, created_at, updated_at | `CHK_INVOICE_STATUS`: pending,completed,cancelled,refunded · `CHK_INVOICE_TYPE`: paid_on_send,paid_on_delivery · `CHK_INVOICE_PAY_METHOD`: cash,card,mobile_payment,account |
| `invoice_item` | id SERIAL | inv_id→invoice, shipment_type, weight, delivery_speed, quantity, unit_price, total_item_cost, notes, created_at, updated_at | — |
| `route` | id SERIAL | driver_id→employee_driver, vehicle_id→vehicle, war_id→warehouse, description, delivery_status, delivery_date, delivery_start_time, delivery_end_time, expected_duration, kms_travelled, driver_notes, is_active, created_at, updated_at | `CHK_ROUTE_STATUS`: not_started,on_going,finished,cancelled |
| `delivery` | id SERIAL | driver_id→employee_driver, route_id→route, inv_id→invoice, client_id→client, war_id→warehouse, tracking_number, description, sender_name/address/phone/email, recipient_name/address/phone/email, item_type, weight, dimensions, status, priority, in_transition, delivery_date, created_at, updated_at | `CHK_DELIVERY_STATUS`: registered,ready,pending,in_transit,completed,cancelled · `CHK_DELIVERY_PRIORITY`: normal,urgent · `CHK_DELIVERY_WEIGHT`: >= 1 |
| `delivery_tracking` | id SERIAL | staff_id→employee_staff, war_id→warehouse, del_id→delivery, status, notes, created_at | `CHK_TRACKING_STATUS`: registered,ready,pending,in_transit,completed,cancelled |

### Foreign Keys (R1–R20)

| # | Constraint | From → To |
|---|-----------|-----------|
| R1 | `FK_CLIENT_INHERITS_USER` | client(id) → "USER"(id) |
| R2 | `FK_EMPLOYEE_INHERITS_USER` | employee(id) → "USER"(id) |
| R3 | `FK_DRIVER_INHERITS_EMPLOYEE` | employee_driver(id) → employee(id) |
| R4 | `FK_STAFF_INHERITS_EMPLOYEE` | employee_staff(id) → employee(id) |
| R5 | `FK_EMPLOYEE_WORKS_AT` | employee(war_id) → warehouse(id) |
| R6 | `FK_INVOICE_REQUESTS` | invoice(client_id) → client(id) |
| R7 | `FK_INVOICE_PROCESSES` | invoice(staff_id) → employee_staff(id) |
| R8 | `FK_INVOICE_RECORDS` | invoice(war_id) → warehouse(id) |
| R9 | `FK_ITEM_CONTAINS` | invoice_item(inv_id) → invoice(id) |
| R10 | `FK_ROUTE_IS_ASSIGNED_TO` | route(driver_id) → employee_driver(id) |
| R11 | `FK_ROUTE_USES` | route(vehicle_id) → vehicle(id) |
| R12 | `FK_ROUTE_DISPATCHES` | route(war_id) → warehouse(id) |
| R13 | `FK_DELIVERY_GENERATES` | delivery(inv_id) → invoice(id) |
| R14 | `FK_DELIVERY_DELIVERS` | delivery(driver_id) → employee_driver(id) |
| R15 | `FK_DELIVERY_SENT_BY` | delivery(client_id) → client(id) |
| R16 | `FK_DELIVERY_BELONGS_TO` | delivery(route_id) → route(id) |
| R17 | `FK_DELIVERY_HANDLES` | delivery(war_id) → warehouse(id) |
| R18 | `FK_TRACKING_LOGS` | delivery_tracking(del_id) → delivery(id) |
| R19 | `FK_TRACKING_REGISTERS_LOGS` | delivery_tracking(staff_id) → employee_staff(id) |
| R20 | `FK_TRACKING_RECORDS_LOGS` | delivery_tracking(war_id) → warehouse(id) |
