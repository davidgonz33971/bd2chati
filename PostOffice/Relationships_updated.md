# Relationship Map (Updated)

All relationships between entities in the PostOffice database schema.

---

## Entity Summary

| Table              | PK         | Foreign Keys                                          |
|--------------------|------------|-------------------------------------------------------|
| User               | id         | -                                                     |
| Client             | id         | user_id                                               |
| Employee           | id         | user_id, warehouse_id                                 |
| EmployeeDriver     | id         | employee_id                                           |
| EmployeeStaff      | id         | employee_id                                           |
| Warehouse          | id         | -                                                     |
| Vehicle            | id         | -                                                     |
| Invoice            | id_invoice | client_id, processed_by_id, warehouse_id              |
| InvoiceItem        | id_item    | invoice_id                                            |
| Route              | id         | driver_id, vehicle_id, warehouse_id                   |
| Delivery           | id         | invoice_id, driver_id, client_id, route_id, warehouse_id |
| DeliveryTracking   | id         | delivery_id, changed_by_id, warehouse_id              |

---

## Inheritance Hierarchy (Exclusive Subtypes)

```
                          USER (id)
                            │
              ┌─────────────┴─────────────┐
              │     MUTUALLY EXCLUSIVE     │
              ▼                            ▼
         CLIENT (id)                 EMPLOYEE (id)
         FK: user_id                 FK: user_id
         1:1 with User               1:1 with User
                                       │
                         ┌─────────────┴─────────────┐
                         │     MUTUALLY EXCLUSIVE     │
                         ▼                            ▼
                  EMPLOYEE_DRIVER (id)         EMPLOYEE_STAFF (id)
                  FK: employee_id              FK: employee_id
                  1:1 with Employee            1:1 with Employee
```

**Rules:**
- A User can be a Client OR an Employee, never both
- An Employee can be a Driver OR Staff, never both
- Admins and Managers exist only in the User table (no Client or Employee record)

---

## All Relationships

### USER

| Relationship | Cardinality | FK Location | ON DELETE | Description |
|---|---|---|---|---|
| User ←→ Client | 1:1 (optional) | Client.user_id → User.id | CASCADE | A User may have one Client profile |
| User ←→ Employee | 1:1 (optional) | Employee.user_id → User.id | CASCADE | A User may have one Employee profile |

**Exclusivity:** Enforced by `trg_check_client_employee_exclusivity` — a User cannot have both a Client AND an Employee record.

---

### CLIENT

| Relationship | Cardinality | FK Location | ON DELETE | Description |
|---|---|---|---|---|
| Client → User | 1:1 (required) | Client.user_id → User.id | CASCADE | Every Client must be a User |
| Client ← Invoice | 1:N | Invoice.client_id → Client.id | SET NULL | A Client can have many Invoices |
| Client ← Delivery | 1:N | Delivery.client_id → Client.id | SET NULL | A Client can have many Deliveries |

---

### EMPLOYEE

| Relationship | Cardinality | FK Location | ON DELETE | Description |
|---|---|---|---|---|
| Employee → User | 1:1 (required) | Employee.user_id → User.id | CASCADE | Every Employee must be a User |
| Employee → Warehouse | N:1 (optional) | Employee.warehouse_id → Warehouse.id | SET NULL | An Employee works at a Warehouse |
| Employee ←→ EmployeeDriver | 1:1 (optional) | EmployeeDriver.employee_id → Employee.id | CASCADE | An Employee may be a Driver |
| Employee ←→ EmployeeStaff | 1:1 (optional) | EmployeeStaff.employee_id → Employee.id | CASCADE | An Employee may be Staff |
| Employee ← Route | 1:N | Route.driver_id → Employee.id | SET NULL | A Driver Employee can be assigned to many Routes |
| Employee ← Delivery | 1:N | Delivery.driver_id → Employee.id | SET NULL | A Driver Employee can be assigned to many Deliveries |
| Employee ← Invoice | 1:N | Invoice.processed_by_id → Employee.id | SET NULL | A Staff Employee can process many Invoices |

**Exclusivity:** Enforced by `trg_check_driver_staff_exclusivity` — an Employee cannot have both a Driver AND a Staff record.

**Sync:** `trg_employee_sync_user_role` keeps User.role aligned with Employee.position.

---

### EMPLOYEE_DRIVER

| Relationship | Cardinality | FK Location | ON DELETE | Description |
|---|---|---|---|---|
| EmployeeDriver → Employee | 1:1 (required) | EmployeeDriver.employee_id → Employee.id | CASCADE | Extension of Employee with license info |

---

### EMPLOYEE_STAFF

| Relationship | Cardinality | FK Location | ON DELETE | Description |
|---|---|---|---|---|
| EmployeeStaff → Employee | 1:1 (required) | EmployeeStaff.employee_id → Employee.id | CASCADE | Extension of Employee with department info |

---

### WAREHOUSE

| Relationship | Cardinality | FK Location | ON DELETE | Description |
|---|---|---|---|---|
| Warehouse ← Employee | 1:N | Employee.warehouse_id → Warehouse.id | SET NULL | A Warehouse has many Employees |
| Warehouse ← Invoice | 1:N | Invoice.warehouse_id → Warehouse.id | SET NULL | Invoices are created at a Warehouse |
| Warehouse ← Route | 1:N | Route.warehouse_id → Warehouse.id | SET NULL | Routes depart from a Warehouse (origin) |
| Warehouse ← Delivery | 1:N | Delivery.warehouse_id → Warehouse.id | SET NULL | Deliveries are received/dispatched at a Warehouse |

---

### VEHICLE

| Relationship | Cardinality | FK Location | ON DELETE | Description |
|---|---|---|---|---|
| Vehicle ← Route | 1:N | Route.vehicle_id → Vehicle.id | SET NULL | A Vehicle can be assigned to many Routes |

**Constraint:** `uq_route_driver_vehicle_date` — same Driver+Vehicle+Date combination cannot repeat.

---

### INVOICE

| Relationship | Cardinality | FK Location | ON DELETE | Description |
|---|---|---|---|---|
| Invoice → Client | N:1 (optional) | Invoice.client_id → Client.id | SET NULL | An Invoice belongs to a Client |
| Invoice → Employee | N:1 (optional) | Invoice.processed_by_id → Employee.id | SET NULL | An Invoice is processed by a Staff Employee |
| Invoice → Warehouse | N:1 (optional) | Invoice.warehouse_id → Warehouse.id | SET NULL | An Invoice is created at a Warehouse |
| Invoice ← InvoiceItem | 1:N | InvoiceItem.invoice_id → Invoice.id_invoice | CASCADE | An Invoice has many line items |
| Invoice ← Delivery | 1:N | Delivery.invoice_id → Invoice.id_invoice | SET NULL | An Invoice can generate one or more Deliveries |

**Triggers:**
- `trg_invoice_update_cost` — recalculates Invoice.cost when InvoiceItems change
- `fn_validate_invoice` — sets status to 'Paid' when paid=TRUE, validates cost >= 0

---

### INVOICE_ITEM

| Relationship | Cardinality | FK Location | ON DELETE | Description |
|---|---|---|---|---|
| InvoiceItem → Invoice | N:1 (required) | InvoiceItem.invoice_id → Invoice.id_invoice | CASCADE | Each item belongs to exactly one Invoice |

**Note:** The item total (`quantity * unit_price`) is calculated on-the-fly in queries via `ExpressionWrapper`, not stored as a column. The sum of all item totals feeds Invoice.cost via `trg_invoice_update_cost`.

---

### ROUTE

| Relationship | Cardinality | FK Location | ON DELETE | Description |
|---|---|---|---|---|
| Route → Employee (Driver) | N:1 (optional) | Route.driver_id → Employee.id | SET NULL | A Route is driven by a Driver |
| Route → Vehicle | N:1 (optional) | Route.vehicle_id → Vehicle.id | SET NULL | A Route uses a Vehicle |
| Route → Warehouse | N:1 (optional) | Route.warehouse_id → Warehouse.id | SET NULL | A Route departs from a Warehouse (origin) |
| Route ← Delivery | 1:N | Delivery.route_id → Route.id | SET NULL | A Route carries many Deliveries |

**Design decisions:**
- **No flattened origin/destination fields.** Origin is derived from the Warehouse FK. Destinations are derived from the Deliveries assigned to this Route (each Delivery has its own `recipient_address`).
- A Route represents a driver's journey: driver + vehicle + warehouse (origin) + date/timing + metrics.
- `trg_route_completed` — when Route status changes to 'Completed', all associated Deliveries are also marked 'Completed'.

**Constraint:** `uq_route_driver_vehicle_date` — prevents double-booking a Driver+Vehicle on the same date.

---

### DELIVERY

| Relationship | Cardinality | FK Location | ON DELETE | Description |
|---|---|---|---|---|
| Delivery → Invoice | N:1 (optional) | Delivery.invoice_id → Invoice.id_invoice | SET NULL | A Delivery may originate from an Invoice |
| Delivery → Employee (Driver) | N:1 (optional) | Delivery.driver_id → Employee.id | SET NULL | A Delivery is assigned to a Driver (denormalized) |
| Delivery → Client | N:1 (optional) | Delivery.client_id → Client.id | SET NULL | A Delivery is requested by a Client |
| Delivery → Route | N:1 (optional) | Delivery.route_id → Route.id | SET NULL | A Delivery is assigned to a Route |
| Delivery → Warehouse | N:1 (optional) | Delivery.warehouse_id → Warehouse.id | SET NULL | A Delivery is received/dispatched at a Warehouse |
| Delivery ← DeliveryTracking | 1:N | DeliveryTracking.delivery_id → Delivery.id | CASCADE | A Delivery has many tracking events (status history) |

**Design decisions:**
- `driver_id` is a **denormalized convenience field**: when a Delivery is assigned to a Route, the driver can be derived via `Route.driver_id`. Keeping it on Delivery enables simpler dashboard queries and allows driver assignment before route creation.
- Sender/recipient info is stored as flattened fields (name, address, phone, email) — these are snapshot values at the time of registration, not FK references, because sender/recipient may not be registered users.
- **Tracking** works from this table: query by `tracking_number` → get current status + JOIN `delivery_tracking` for full timeline. JOIN Route for driver/vehicle/timing. JOIN Warehouse (via Route) for origin.

---

### DELIVERY_TRACKING

| Relationship | Cardinality | FK Location | ON DELETE | Description |
|---|---|---|---|---|
| DeliveryTracking → Delivery | N:1 (required) | DeliveryTracking.delivery_id → Delivery.id | CASCADE | Each event belongs to one Delivery |
| DeliveryTracking → Employee | N:1 (optional) | DeliveryTracking.changed_by_id → Employee.id | SET NULL | Who changed the status |
| DeliveryTracking → Warehouse | N:1 (optional) | DeliveryTracking.warehouse_id → Warehouse.id | SET NULL | Where the package was at the time of the event |

**Design decisions:**
- This is an **append-only event log** — rows are only inserted, never updated or deleted.
- Populated automatically by `trg_delivery_tracking_log` trigger on delivery status changes.
- Also populated by `sp_update_delivery_status()` procedure which sets `changed_by_id` and `warehouse_id` before the trigger fires.
- `delivery.status` remains as the **current** status (snapshot). `delivery_tracking` provides the **full history**.

**Example timeline:**
```
PT2025010001 - Livros técnicos
──────────────────────────────────────────────────────────────
2026-02-06 09:15  Registered     Armazém Central Lisboa    (Staff: João)
2026-02-06 14:00  Ready          Armazém Central Lisboa    (Staff: João)
2026-02-06 14:30  In Transit     -                         (Driver: Pedro)
2026-02-07 10:20  Completed      -                         (Driver: Pedro)
```

---

## Business Flow

```
1. CLIENT or STAFF creates INVOICE
       │
       ▼
2. INVOICE generates DELIVERY (status: Registered)
   - Sender/recipient info captured
   - Tracking number assigned
   - Warehouse set (where package was received)
   - ★ TRACKING EVENT: "Registered" logged automatically (trg_delivery_tracking_log)
       │
       ▼
3. ADMIN creates ROUTE
   - Assigns Driver + Vehicle + Warehouse (origin) + Date
       │
       ▼
4. ADMIN assigns DELIVERY to ROUTE (sets delivery.route_id)
   - Delivery status → Ready
   - ★ TRACKING EVENT: "Ready" logged automatically
       │
       ▼
5. DRIVER starts ROUTE
   - Route status → InProgress
   - Delivery status → In Transit
   - ★ TRACKING EVENT: "In Transit" logged automatically
       │
       ▼
6. DRIVER completes ROUTE
   - Route status → Completed
   - All Deliveries on Route → Completed (via trg_route_completed)
   - ★ TRACKING EVENT: "Completed" logged automatically for each delivery
```

---

## Tracking Query Examples

### Current status + route info
```sql
SELECT
    d.tracking_number,
    d.status,
    d.priority,
    d.sender_name,
    d.sender_address,
    d.recipient_name,
    d.recipient_address,
    d.weight,
    d.item_type,
    w.name       AS origin_warehouse,
    w.address    AS origin_address,
    r.delivery_date,
    r.delivery_start_time,
    r.delivery_status AS route_status,
    u.full_name  AS driver_name,
    v.plate_number,
    v.vehicle_type
FROM postoffice_app_delivery d
LEFT JOIN postoffice_app_route r     ON d.route_id = r.id
LEFT JOIN postoffice_app_warehouse w ON r.warehouse_id = w.id
LEFT JOIN postoffice_app_employee e  ON r.driver_id = e.id
LEFT JOIN postoffice_app_user u      ON e.user_id = u.id
LEFT JOIN postoffice_app_vehicle v   ON r.vehicle_id = v.id
WHERE d.tracking_number = 'PT2025010001';
```

### Full tracking timeline (event history)
```sql
SELECT
    t.created_at     AS event_time,
    t.status         AS event_status,
    w.name           AS location,
    u.full_name      AS changed_by,
    t.notes
FROM postoffice_app_delivery_tracking t
JOIN postoffice_app_delivery d          ON t.delivery_id = d.id
LEFT JOIN postoffice_app_employee e     ON t.changed_by_id = e.id
LEFT JOIN postoffice_app_user u         ON e.user_id = u.id
LEFT JOIN postoffice_app_warehouse w    ON t.warehouse_id = w.id
WHERE d.tracking_number = 'PT2025010001'
ORDER BY t.created_at ASC;
```

---

## Relationship Diagram (Simplified)

```
WAREHOUSE ──────────────────────────────────────────────┐
    │ 1:N                                                │ 1:N
    ▼                                                    ▼
EMPLOYEE ◄──── 1:1 ────► USER ◄──── 1:1 ────► CLIENT   INVOICE
    │                                            │        │ 1:N
    │ 1:N                                   1:N  │        ▼
    ▼                                            │   INVOICE_ITEM
  ROUTE ◄─── N:1 ──── VEHICLE                   │
    │ 1:N                                        │
    ▼                                            │
DELIVERY ◄───────────────────────────────────────┘
    │ 1:N
    ▼
DELIVERY_TRACKING (event log / timeline)
```
