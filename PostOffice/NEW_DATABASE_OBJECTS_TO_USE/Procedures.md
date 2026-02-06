## 5. PROCEDURES (CRUD Operations)

### 5.1 User & Authentication

| Current ORM                    | Procedure Name   | Parameters                                                   | Purpose                        |
|--------------------------------|------------------|--------------------------------------------------------------|--------------------------------|
| `User.objects.create_user()`   | `sp_create_user` | username, email, password, full_name, contact, address, etc. | Create new user with hashed pw |
| `user.save()` on profile update| `sp_update_user` | user_id, fields...                                           | Update user profile            |
| User deletion (if needed)      | `sp_delete_user` | user_id                                                      | Soft delete user               |

### 5.2 Employee Management

| Current ORM                        | Procedure Name       | Parameters                                          | Purpose                                   |
|------------------------------------|----------------------|-----------------------------------------------------|-------------------------------------------|
| `Employee.objects.create()` + rel. | `sp_create_employee` | user_id, position, schedule, wage, driver/staff info| Create employee + related + sync role     |
| `employee.save()` + role sync      | `sp_update_employee` | employee_id, fields...                              | Update employee and sync role             |
| `employee.delete()`                | `sp_delete_employee` | employee_id                                         | Delete employee and related records       |

### 5.3 Delivery Management

| Current ORM                 | Procedure Name        | Parameters        | Purpose                          |
|-----------------------------|-----------------------|-------------------|----------------------------------|
| `Delivery.objects.create()` | `sp_create_delivery`  | all 20+ fields    | Create delivery with validation  |
| `delivery.save()`           | `sp_update_delivery`  | delivery_id, ...  | Update with status workflow check|
| `delivery.save()` (status only) | `sp_update_delivery_status` | delivery_id, new_status, employee_id, warehouse_id, notes | Update status + insert tracking event |
| `delivery.delete()`         | `sp_delete_delivery`  | delivery_id       | Soft delete delivery             |
| Bulk import from JSON       | `sp_import_deliveries`| JSONB array       | Bulk insert with validation      |

### 5.4 Route Management

| Current ORM              | Procedure Name     | Parameters      | Purpose                              |
|--------------------------|--------------------|-----------------|--------------------------------------|
| `Route.objects.create()` | `sp_create_route`  | all 16 fields   | Create route with time validation    |
| `route.save()`           | `sp_update_route`  | route_id, ...   | Update route                         |
| `route.delete()`         | `sp_delete_route`  | route_id        | Delete route (check no active deliv.)|
| Bulk import from JSON    | `sp_import_routes` | JSONB array     | Bulk insert with validation          |

### 5.5 Vehicle Management

| Current ORM                | Procedure Name       | Parameters      | Purpose                       |
|----------------------------|----------------------|-----------------|-------------------------------|
| `Vehicle.objects.create()` | `sp_create_vehicle`  | all 9 fields    | Create vehicle with validation|
| `vehicle.save()`           | `sp_update_vehicle`  | vehicle_id, ... | Update vehicle                |
| `vehicle.delete()`         | `sp_delete_vehicle`  | vehicle_id      | Delete (check no active routes)|
| Bulk import from JSON      | `sp_import_vehicles` | JSONB array     | Bulk insert                   |

### 5.6 Warehouse Management

| Current ORM                  | Procedure Name         | Parameters        | Purpose                        |
|------------------------------|------------------------|-------------------|--------------------------------|
| `Warehouse.objects.create()` | `sp_create_warehouse`  | all 6 fields      | Create with schedule validation|
| `warehouse.save()`           | `sp_update_warehouse`  | warehouse_id, ... | Update warehouse               |
| `warehouse.delete()`         | `sp_delete_warehouse`  | warehouse_id      | Delete warehouse               |
| Bulk import from JSON        | `sp_import_warehouses` | JSONB array       | Bulk insert                    |

### 5.7 Invoice Management

| Current ORM                   | Procedure Name        | Parameters                              | Purpose                      |
|-------------------------------|-----------------------|-----------------------------------------|------------------------------|
| `Invoice.objects.create()`    | `sp_create_invoice`   | user_id, type, payment_method, etc.     | Create invoice header        |
| `InvoiceItem.objects.create()`| `sp_add_invoice_item` | invoice_id, shipment_type, weight, etc. | Add item and update total    |
| `invoice.save()`              | `sp_update_invoice`   | invoice_id, fields...                   | Update invoice               |
| `invoice.delete()`            | `sp_delete_invoice`   | invoice_id                              | Soft delete invoice          |
| Bulk import from JSON         | `sp_import_invoices`  | JSONB array                             | Bulk insert invoices + items |