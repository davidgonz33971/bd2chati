## 4. FUNCTIONS (Calculations & Queries)

### 4.1 Calculation Functions

| Current Logic                        | Function Name                     | Returns | Purpose                            |
|--------------------------------------|-----------------------------------|---------|------------------------------------|
| `subtotal * Decimal("0.23")` in Python | `fn_calculate_tax(amount, rate)`  | DECIMAL | Calculate tax with configurable rate |
| `quantity * unit_price` in Python    | `fn_calculate_item_total(qty, price)` | DECIMAL | Calculate invoice item total       |
| Subtotal calculated in view loop     | `fn_invoice_subtotal(invoice_id)` | DECIMAL | Sum all items for an invoice       |
| Total with tax in Python             | `fn_invoice_total(invoice_id)`    | DECIMAL | Subtotal + tax                     |

### 4.2 Query Functions (Return Tables)

| Current Logic                            | Function Name                              | Returns | Purpose                                  |
|------------------------------------------|--------------------------------------------|---------|------------------------------------------|
| `Delivery.objects.filter(client_id=X)`   | `fn_get_client_deliveries(client_id)`      | TABLE   | Get deliveries for specific client       |
| `Delivery.objects.filter(driver_id=X)`   | `fn_get_driver_deliveries(driver_id)`      | TABLE   | Get deliveries for specific driver       |
| No tracking history                      | `fn_get_delivery_tracking(tracking_num)`   | TABLE   | Get full tracking timeline by tracking number (joins delivery_tracking, employee, warehouse) |
| Dashboard counts per role                | `fn_get_dashboard_stats(user_id, role)`    | TABLE   | Role-specific dashboard data             |
| Notification query with time filter      | `fn_get_recent_notifications(email, mins)` | TABLE   | MongoDB replacement or PG notifications  |

### 4.3 Validation Functions

| Current Logic                  | Function Name                          | Returns | Purpose                            |
|--------------------------------|----------------------------------------|---------|------------------------------------|
| Form validates license expiry  | `fn_is_license_valid(expiry_date)`     | BOOLEAN | Check if license not expired       |
| Form validates year range      | `fn_is_valid_year(year)`               | BOOLEAN | Check year between 1900-2100       |
| Status transition validation   | `fn_is_valid_status_transition(old, new)` | BOOLEAN | Check if status change is allowed  |