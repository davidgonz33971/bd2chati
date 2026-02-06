## 3. TRIGGER FUNCTIONS (Automatic Actions)

### 3.1 Data Integrity Triggers

| Current Logic                            | Trigger Name                  | Event                                    | Purpose                                            |
|------------------------------------------|-------------------------------|------------------------------------------|----------------------------------------------------|
| `Employee.save()` syncs `user.role`      | `trg_employee_sync_user_role` | AFTER INSERT/UPDATE ON employee          | Auto-update user role when position changes        |
| `InvoiceItem.save()` calculates `total`  | `trg_invoice_item_calc_total` | BEFORE INSERT/UPDATE ON invoice_item     | Calculate `quantity * unit_price`                  |
| Invoice cost should sum items            | `trg_invoice_update_cost`     | AFTER INSERT/UPDATE/DELETE ON invoice_item | Recalculate invoice total cost                     |

### 3.2 Tracking Triggers

| Current Logic                    | Trigger Name                  | Event                                         | Purpose                                            |
|----------------------------------|-------------------------------|-----------------------------------------------|----------------------------------------------------|
| `RAISE NOTICE` only (transient)  | `trg_delivery_tracking_log`   | AFTER INSERT OR UPDATE OF status ON delivery  | Insert event into delivery_tracking table          |

**How it works:**
- On INSERT: logs initial status (e.g. 'Registered') as first tracking event
- On UPDATE of status: logs the new status with timestamp
- The trigger captures `delivery_id`, `NEW.status`, and `NOW()` automatically
- `changed_by_id` and `warehouse_id` are set by `sp_update_delivery_status()` before the trigger fires

### 3.3 Audit Trail Triggers

| Current Logic          | Trigger Name              | Event                                    | Purpose                              |
|------------------------|---------------------------|------------------------------------------|--------------------------------------|
| Hard delete everywhere | `trg_delivery_soft_delete`| BEFORE DELETE ON delivery                | Set `is_deleted=true` instead        |
| Hard delete everywhere | `trg_invoice_soft_delete` | BEFORE DELETE ON invoice                 | Set `is_deleted=true` instead        |
| No audit trail         | `trg_audit_log`           | AFTER INSERT/UPDATE/DELETE ON all tables | Log changes to audit table           |

### 3.4 Validation Triggers

| Current Logic                            | Trigger Name                   | Event                            | Purpose                              |
|------------------------------------------|--------------------------------|----------------------------------|--------------------------------------|
| Delivery status can change to anything   | `trg_delivery_status_workflow` | BEFORE UPDATE ON delivery        | Enforce valid status transitions     |
| No timestamp validation at DB level      | `trg_delivery_timestamp_check` | BEFORE INSERT/UPDATE ON delivery | Ensure `updated_at >= registered_at` |
| Route times not validated at DB          | `trg_route_time_check`         | BEFORE INSERT/UPDATE ON route    | Ensure `end_time > start_time`       |
| Warehouse schedule not validated at DB   | `trg_warehouse_schedule_check` | BEFORE INSERT/UPDATE ON warehouse| Ensure `close_time > open_time`      |