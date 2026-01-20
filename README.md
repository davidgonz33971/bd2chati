Admin user: adminuser / password123
Client user: clientuser / password123
Driver user: driveruser / password123
Staff user: staffuser / password123
Manager user: manageruser / password123

# TO FINISH:
    1. Admin panels should import/export data to json/csv
    2. Fix invoice:
        "lines" on pgsql
        Trigger to calcutate total of invoice costs and stored it in an additional field
    4. TP13

# Implemented on 29/11/25
- 0002_triggers_integracion.py -> **Functions and Triggers**
fn_update_delivery_timestamp()
fn_log_delivery_created()
fn_log_delivery_status_change()
fn_validate_delivery()
fn_validate_invoice()
fn_validate_driver()
fn_route_status()
and recreates triggers for each model

- 0003_export_functions.py -> **CSV Export pgSQL**
export_warehouses_csv()
export_vehicles_csv()
export_routes_csv()
export_deliveries_csv()
export_invoices_csv()

### Updated DB:
- Now runs fully on **PostgreSQL** for all operational data while keeping **MongoDB only for notifications**.
- Django ORM is the core interface for all business models, giving strong relational integrity and predictable CRUD behavior.
- Models are fully normalized—Users, Employees, Vehicles, Warehouses, Routes, Deliveries, and Invoices all live in PostgreSQL with explicit foreign keys and validation logic. - Employees follow a strict hierarchy linking Users → Employee → (Driver/Staff), with automatic role synchronization.

# views.py, centralizes all business logic:
* Role-based access control through a custom decorator
* Unified CRUD patterns (list, form, delete with POST-only protection)
* Dashboard statistics per role
* Pagination and queryset optimization
* Notification helper writing to MongoDB

# forms.py
Forms (`forms.py`) now enforce business rules through custom `clean()` methods, date/time widgets, and stricter validation (weights, capacities, dates, driver license expiry, wage, etc.).

# models.py
Models (`models.py`) include constraints, validators, ordering, and PROTECT-based FK rules to avoid accidental orphaning.

