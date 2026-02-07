## 2. MATERIALIZED VIEWS (Cached Aggregations)

### 2.1 Dashboard Statistics

| Current ORM                                                              | New Materialized View | Refresh Strategy       |
|--------------------------------------------------------------------------|-----------------------|------------------------|
| `Vehicle.objects.count()`                                                | `mv_dashboard_stats`  | On demand or scheduled |
| `Delivery.objects.count()`                                               | (combined in above)   |                        |
| `User.objects.filter(role="client").count()`                             | (combined in above)   |                        |
| `Employee.objects.count()`                                               | (combined in above)   |                        |
| `Route.objects.exclude(delivery_status__in=["Completed","Cancelled"]).count()` | (combined in above)   |                        |
| `Delivery.objects.filter(status="Pending").count()`                      | (combined in above)   |                        |
| `Invoice.objects.count()`                                                | (combined in above)   |                        |

**Note:** Delivery tracking (`delivery_tracking` table) does NOT use a materialized view — tracking data must be real-time, not cached. Use `v_delivery_tracking` (regular view) or `fn_get_delivery_tracking()` instead.

### 2.2 Invoice Summaries

| Current ORM                                          | New Materialized View | Refresh Strategy        |
|------------------------------------------------------|-----------------------|-------------------------|
| `items.aggregate(subtotal=Sum('total_price'))` per invoice | `mv_invoice_totals`   | On invoice/item change  |