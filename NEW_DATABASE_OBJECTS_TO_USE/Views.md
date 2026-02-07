## 1. VIEWS (Read-Only Queries)

### 1.1 List Views with Relationships

| Current ORM                                                      | New View Name          | Purpose                                        |
|------------------------------------------------------------------|------------------------|------------------------------------------------|
| `Delivery.objects.select_related("driver", "client", "route").all()` | `v_deliveries_full`    | Deliveries with driver, client, route joined   |
| `Route.objects.select_related("driver", "vehicle").all()`        | `v_routes_full`        | Routes with driver and vehicle info joined     |
| `Employee.objects.select_related("user").all()`                  | `v_employees_full`     | Employees with user account info joined        |
| `Invoice.objects.prefetch_related('items')`                      | `v_invoices_with_items`| Invoices with aggregated item totals           |

### 1.2 Tracking Views

| Current ORM                                                      | New View Name          | Purpose                                        |
|------------------------------------------------------------------|------------------------|------------------------------------------------|
| No tracking history (only current status)                        | `v_delivery_tracking`  | Full tracking timeline for a delivery (joins delivery_tracking with delivery, employee, warehouse) |

### 1.3 Filtered List Views

| Current ORM                                      | New View Name          | Purpose                                    |
|--------------------------------------------------|------------------------|--------------------------------------------|
| `Delivery.objects.filter(client=user)`           | `v_client_deliveries`  | Use with WHERE clause or create function   |
| `Delivery.objects.filter(driver=employee)`       | `v_driver_deliveries`  | Use with WHERE clause or create function   |
| `User.objects.filter(role="client")`             | `v_clients`            | All users with client role                 |
| `User.objects.exclude(role__in=["admin", "client"])` | `v_potential_employees`| Users eligible to become employees         |

### 1.4 Export Views (JSON format preparation)

| Current ORM                       | New View Name        | Purpose                  |
|-----------------------------------|----------------------|--------------------------|
| `Delivery.objects.all().values()` | `v_deliveries_export`| Formatted for JSON export|
| `Route.objects.all().values()`    | `v_routes_export`    | Formatted for JSON export|
| `Vehicle.objects.all().values()`  | `v_vehicles_export`  | Formatted for JSON export|
| `Warehouse.objects.all().values()`| `v_warehouses_export`| Formatted for JSON export|
| `Invoice.objects.all().values()`  | `v_invoices_export`  | Formatted for JSON export|