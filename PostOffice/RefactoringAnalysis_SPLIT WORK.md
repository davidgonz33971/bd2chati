# Refactoring Analysis: Django ORM to Database Objects

This document maps all current Django ORM operations to their appropriate PostgreSQL database objects (Views, Materialized Views, Triggers, Functions, Procedures).


## SUMMARY of all OBJECTS to implement

### By Database Object:
| Type                   | Count | Objects                                          |
|------------------------|-------|--------------------------------------------------|
| **VIEWS**              | 15    | List views, filtered views, export views, tracking |
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
| Delivery       | 4     | -         | 4        | 3         | 5                      | 16 DAVID
| Invoice        | 2     | 1         | 1        | 3         | 4                      | 11 ___
| InvoiceItem    | -     | -         | 2        | 1         | 1                      | 4
| Dashboard      | -     | 1         | -        | 1         | -                      | 3  ROD
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

### Current Implementation (Django ORM)

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
-- File: migrations/sql/triggers/trg_employee_sync_user_role.sql

CREATE OR REPLACE FUNCTION fn_sync_employee_user_role()
RETURNS TRIGGER AS $$
BEGIN
    -- Automatically update user role when employee position changes
    IF NEW.position = 'Driver' THEN
        UPDATE postoffice_app_user
        SET role = 'driver', updated_at = NOW()
        WHERE id = NEW.user_id;
    ELSIF NEW.position = 'Staff' THEN
        UPDATE postoffice_app_user
        SET role = 'staff', updated_at = NOW()
        WHERE id = NEW.user_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS trg_employee_sync_user_role ON postoffice_app_employee;
CREATE TRIGGER trg_employee_sync_user_role
    AFTER INSERT OR UPDATE OF position ON postoffice_app_employee
    FOR EACH ROW
    EXECUTE FUNCTION fn_sync_employee_user_role();
```

#### B. Stored Procedure - Create Employee (with driver/staff info)

```sql
-- File: migrations/sql/procedures/sp_create_employee.sql

CREATE OR REPLACE PROCEDURE sp_create_employee(
    -- User params
    p_username VARCHAR(150),
    p_email VARCHAR(254),
    p_password VARCHAR(128),  -- Already hashed by Django
    p_full_name VARCHAR(150),
    p_contact VARCHAR(50),
    p_address VARCHAR(255),
    p_tax_id VARCHAR(50),
    -- Employee params
    p_position VARCHAR(50),
    p_schedule VARCHAR(50),
    p_wage DECIMAL(8,2),
    p_hire_date DATE,
    -- Driver params (nullable)
    p_license_number VARCHAR(50) DEFAULT NULL,
    p_license_category VARCHAR(10) DEFAULT NULL,
    p_license_expiry DATE DEFAULT NULL,
    p_driving_experience INT DEFAULT NULL,
    p_driver_status VARCHAR(50) DEFAULT NULL,
    -- Staff params (nullable)
    p_department VARCHAR(100) DEFAULT NULL,
    -- Output
    OUT o_employee_id INT,
    OUT o_user_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id INT;
    v_employee_id INT;
BEGIN
    -- Validate position
    IF p_position NOT IN ('Driver', 'Staff') THEN
        RAISE EXCEPTION 'Invalid position: %. Must be Driver or Staff', p_position;
    END IF;

    -- Validate driver has required fields
    IF p_position = 'Driver' AND (p_license_number IS NULL OR p_license_expiry IS NULL) THEN
        RAISE EXCEPTION 'Driver position requires license_number and license_expiry';
    END IF;

    -- Validate license not expired
    IF p_position = 'Driver' AND p_license_expiry <= CURRENT_DATE THEN
        RAISE EXCEPTION 'License expiry date must be in the future';
    END IF;

    -- Validate staff has department
    IF p_position = 'Staff' AND p_department IS NULL THEN
        RAISE EXCEPTION 'Staff position requires department';
    END IF;

    -- Validate wage
    IF p_wage < 0 THEN
        RAISE EXCEPTION 'Wage cannot be negative';
    END IF;

    -- Create user (role will be set by trigger after employee insert)
    INSERT INTO postoffice_app_user (
        username, email, password, full_name, contact, address, tax_id,
        role, is_superuser, is_staff, is_active, date_joined, created_at, updated_at
    ) VALUES (
        p_username, p_email, p_password, p_full_name, p_contact, p_address, p_tax_id,
        'client',  -- Temporary, trigger will update
        FALSE, FALSE, TRUE, NOW(), NOW(), NOW()
    ) RETURNING id INTO v_user_id;

    -- Create employee (trigger fires and updates user.role)
    INSERT INTO postoffice_app_employee (
        user_id, position, schedule, wage, is_active, hire_date
    ) VALUES (
        v_user_id, p_position, p_schedule, p_wage, TRUE, p_hire_date
    ) RETURNING id INTO v_employee_id;

    -- Create driver-specific record if Driver
    IF p_position = 'Driver' THEN
        INSERT INTO postoffice_app_employeedriver (
            employee_id, license_number, license_category,
            license_expiry_date, driving_experience_years, driver_status
        ) VALUES (
            v_employee_id, p_license_number, p_license_category,
            p_license_expiry, p_driving_experience, p_driver_status
        );
    END IF;

    -- Create staff-specific record if Staff
    IF p_position = 'Staff' THEN
        INSERT INTO postoffice_app_employeestaff (
            employee_id, department
        ) VALUES (
            v_employee_id, p_department
        );
    END IF;

    -- Set output parameters
    o_employee_id := v_employee_id;
    o_user_id := v_user_id;

END;
$$;
```

#### C. View - Employees list with user info

```sql
-- File: migrations/sql/views/v_employees_full.sql

CREATE OR REPLACE VIEW v_employees_full AS
SELECT
    e.id AS employee_id,
    e.position,
    e.schedule,
    e.wage,
    e.is_active,
    e.hire_date,
    u.id AS user_id,
    u.username,
    u.email,
    u.full_name,
    u.contact,
    u.role,
    -- Driver info (NULL if not driver)
    ed.license_number,
    ed.license_category,
    ed.license_expiry_date,
    ed.driving_experience_years,
    ed.driver_status,
    -- Staff info (NULL if not staff)
    es.department
FROM postoffice_app_employee e
JOIN postoffice_app_user u ON e.user_id = u.id
LEFT JOIN postoffice_app_employeedriver ed ON e.id = ed.employee_id
LEFT JOIN postoffice_app_employeestaff es ON e.id = es.employee_id
WHERE e.is_active = TRUE
ORDER BY u.full_name;
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

        position = request.POST.get("position")
        forms_valid = user_form.is_valid() and emp_form.is_valid()

        if position == "Driver":
            forms_valid = forms_valid and driver_form.is_valid()
        elif position == "Staff":
            forms_valid = forms_valid and staff_form.is_valid()

        if forms_valid:
            try:
                # Hash password in Python (Django's hasher)
                hashed_password = make_password(user_form.cleaned_data["password"])

                # Call stored procedure - single atomic transaction
                with connection.cursor() as cursor:
                    cursor.execute("""
                        CALL sp_create_employee(
                            %s, %s, %s, %s, %s, %s, %s,  -- user params
                            %s, %s, %s, %s,              -- employee params
                            %s, %s, %s, %s, %s,          -- driver params
                            %s,                          -- staff params
                            NULL, NULL                   -- OUT params
                        )
                    """, [
                        # User params
                        user_form.cleaned_data["username"],
                        user_form.cleaned_data["email"],
                        hashed_password,
                        user_form.cleaned_data["full_name"],
                        user_form.cleaned_data["contact"],
                        user_form.cleaned_data["address"],
                        user_form.cleaned_data.get("tax_id", ""),
                        # Employee params
                        emp_form.cleaned_data["position"],
                        emp_form.cleaned_data["schedule"],
                        emp_form.cleaned_data["wage"],
                        emp_form.cleaned_data.get("hire_date"),
                        # Driver params (None if not driver)
                        driver_form.cleaned_data.get("license_number") if position == "Driver" else None,
                        driver_form.cleaned_data.get("license_category") if position == "Driver" else None,
                        driver_form.cleaned_data.get("license_expiry_date") if position == "Driver" else None,
                        driver_form.cleaned_data.get("driving_experience_years") if position == "Driver" else None,
                        driver_form.cleaned_data.get("driver_status") if position == "Driver" else None,
                        # Staff params (None if not staff)
                        staff_form.cleaned_data.get("department") if position == "Staff" else None,
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
