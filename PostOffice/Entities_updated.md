# Entities (Updated)

All tables in the PostOffice database, their purpose, columns, constraints, and foreign keys.

---

## Inheritance Structure

```
USER (base)
  ├── CLIENT (exclusive)      ── users who request delivery services
  └── EMPLOYEE (exclusive)    ── users who work at the post office
        ├── EMPLOYEE_DRIVER (exclusive) ── drivers who deliver packages
        └── EMPLOYEE_STAFF (exclusive)  ── staff who work inside the PO

Exclusivity Rules:
  - A User can be Client OR Employee, never both
  - An Employee can be Driver OR Staff, never both
  - Admins/Managers are Users without Client/Employee record
```

---

## USER
**Purpose:** Base table for all system users. Stores common identity and authentication info. Admins and Managers exist only in this table.

| Column           | Type          | Constraints                        | Description                              |
|------------------|---------------|------------------------------------|------------------------------------------|
| id               | SERIAL        | PK                                 | Unique user identifier                   |
| password         | VARCHAR(128)  | NOT NULL                           | Django hashed password                   |
| is_superuser     | BOOLEAN       | NOT NULL, DEFAULT FALSE            | Django superuser/admin flag              |
| username         | VARCHAR(150)  | NOT NULL, UNIQUE                   | Login username                           |
| first_name       | VARCHAR(150)  | NOT NULL, DEFAULT ''               | Django first name field                  |
| last_name        | VARCHAR(150)  | NOT NULL, DEFAULT ''               | Django last name field                   |
| email            | VARCHAR(254)  | NOT NULL, DEFAULT ''               | Email address                            |
| is_staff         | BOOLEAN       | NOT NULL, DEFAULT FALSE            | Django staff flag (admin panel access)   |
| contact          | VARCHAR(50)   | DEFAULT ''                         | Phone/contact number                     |
| address          | VARCHAR(255)  | DEFAULT ''                         | Physical address                         |
| role             | VARCHAR(20)   | NOT NULL, DEFAULT 'client'         | System role                              |
| created_at       | TIMESTAMPTZ   | NOT NULL, DEFAULT NOW()            | Record creation timestamp                |
| updated_at       | TIMESTAMPTZ   | NOT NULL, DEFAULT NOW()            | Last update timestamp                    |

**CHECK:** `role IN ('admin', 'client', 'driver', 'staff', 'manager')`

---

## CLIENT
**Purpose:** Extension of User for customers who request delivery services. Separated from User to enforce exclusivity with Employee and to store client-specific data (tax ID for invoicing).

| Column   | Type         | Constraints              | Description                                  |
|----------|--------------|--------------------------|----------------------------------------------|
| id       | SERIAL       | PK                       | Client identifier (distinct from user_id)    |
| user_id  | INTEGER      | NOT NULL, UNIQUE, FK     | References User.id (CASCADE)                 |
| tax_id   | VARCHAR(50)  | DEFAULT ''               | NIF for invoicing (may differ from personal) |

---

## EMPLOYEE
**Purpose:** Extension of User for post office workers. Contains employment details common to all employees (drivers and staff). Linked to a Warehouse where the employee works.

| Column       | Type         | Constraints                  | Description                          |
|--------------|--------------|------------------------------|--------------------------------------|
| id           | SERIAL       | PK                           | Employee identifier                  |
| user_id      | INTEGER      | NOT NULL, UNIQUE, FK         | References User.id (CASCADE)         |
| warehouse_id | INTEGER      | NULL, FK                     | References Warehouse.id (SET NULL)   |
| position     | VARCHAR(20)  | NOT NULL                     | Employee type                        |
| schedule     | VARCHAR(50)  | DEFAULT ''                   | Work schedule (e.g. "08:00-16:00")   |
| wage         | DECIMAL(8,2) | NOT NULL, DEFAULT 0.00       | Salary/wage                          |
| is_active    | BOOLEAN      | NOT NULL, DEFAULT TRUE       | Whether currently employed           |
| hire_date    | DATE         | NULL                         | Date of hire                         |

**CHECK:** `position IN ('Driver', 'Staff')`, `wage >= 0`

---

## EMPLOYEE_DRIVER
**Purpose:** Sub-entity of Employee for drivers only. Stores license and driving-specific information. Exclusive with EmployeeStaff.

| Column                   | Type         | Constraints                  | Description                         |
|--------------------------|--------------|------------------------------|-------------------------------------|
| id                       | SERIAL       | PK                           | Driver record identifier            |
| employee_id              | INTEGER      | NOT NULL, UNIQUE, FK         | References Employee.id (CASCADE)    |
| license_number           | VARCHAR(50)  | NOT NULL                     | Driving license number              |
| license_category         | VARCHAR(10)  | NOT NULL                     | License category (A, B, C, D)       |
| license_expiry_date      | DATE         | NOT NULL                     | License expiration date             |
| driving_experience_years | INTEGER      | NOT NULL, DEFAULT 0          | Years of driving experience         |
| driver_status            | VARCHAR(50)  | NOT NULL, DEFAULT 'Available'| Current availability                |

**CHECK:** `driving_experience_years >= 0`, `driver_status IN ('Available', 'OnDuty', 'OffDuty', 'OnLeave')`

---

## EMPLOYEE_STAFF
**Purpose:** Sub-entity of Employee for office/warehouse staff. Stores department assignment. Exclusive with EmployeeDriver.

| Column      | Type         | Constraints              | Description                        |
|-------------|--------------|--------------------------|------------------------------------|
| id          | SERIAL       | PK                       | Staff record identifier            |
| employee_id | INTEGER      | NOT NULL, UNIQUE, FK     | References Employee.id (CASCADE)   |
| department  | VARCHAR(32)  | NOT NULL                 | Department (Customer_Service, Sorting, Administration) |

---

## WAREHOUSE
**Purpose:** Physical post office locations/warehouses. Serves as dispatch origin for Routes and receive point for Deliveries. Employees are assigned to a Warehouse.

| Column                   | Type         | Constraints                  | Description                        |
|--------------------------|--------------|------------------------------|------------------------------------|
| id                       | SERIAL       | PK                           | Warehouse identifier               |
| name                     | VARCHAR(100) | NOT NULL                     | Warehouse/store name               |
| address                  | VARCHAR(200) | NOT NULL                     | Physical address                   |
| contact                  | VARCHAR(50)  | NOT NULL                     | Phone/contact number               |
| schedule_open            | TIME         | NOT NULL                     | Opening time                       |
| schedule_close           | TIME         | NOT NULL                     | Closing time                       |
| schedule                 | TEXT         | NOT NULL                     | Schedule description               |
| maximum_storage_capacity | INTEGER      | NOT NULL                     | Max storage capacity               |
| is_active                | BOOLEAN      | NOT NULL, DEFAULT TRUE       | Whether warehouse is operational   |
| created_at               | TIMESTAMPTZ  | NOT NULL, DEFAULT NOW()      | Record creation timestamp          |
| updated_at               | TIMESTAMPTZ  | NOT NULL, DEFAULT NOW()      | Last update timestamp              |

**CHECK:** `maximum_storage_capacity > 0`, `schedule_close > schedule_open`

---

## VEHICLE
**Purpose:** Fleet vehicles used for deliveries. Assigned to Routes. Tracks maintenance and availability status.

| Column                 | Type          | Constraints                    | Description                        |
|------------------------|---------------|--------------------------------|------------------------------------|
| id                     | SERIAL        | PK                             | Vehicle identifier                 |
| vehicle_type           | VARCHAR(100)  | NOT NULL                       | Type (Van, Truck, Motorcycle, etc) |
| plate_number           | VARCHAR(20)   | NOT NULL, UNIQUE               | License plate                      |
| capacity               | DECIMAL(10,2) | NOT NULL                       | Weight capacity (kg) or volume     |
| brand                  | VARCHAR(100)  | NOT NULL                       | Manufacturer (Ford, Mercedes, etc) |
| model                  | VARCHAR(100)  | NOT NULL                       | Vehicle model                      |
| vehicle_status         | VARCHAR(50)   | NOT NULL, DEFAULT 'Available'  | Current status                     |
| year                   | INTEGER       | NOT NULL                       | Manufacturing year                 |
| fuel_type              | VARCHAR(50)   | NOT NULL                       | Fuel type (Diesel, Electric, etc)  |
| last_maintenance_date  | DATE          | NOT NULL                       | Last maintenance date              |
| is_active              | BOOLEAN       | NOT NULL, DEFAULT TRUE         | Whether vehicle is in fleet        |
| created_at             | TIMESTAMPTZ   | NOT NULL, DEFAULT NOW()        | Record creation timestamp          |
| updated_at             | TIMESTAMPTZ   | NOT NULL, DEFAULT NOW()        | Last update timestamp              |

**CHECK:** `capacity > 0`, `year BETWEEN 1900 AND 2100`, `vehicle_status IN ('Available', 'InUse', 'Maintenance', 'Retired')`

---

## INVOICE
**Purpose:** Record of items/services a client wants to send. Created by Staff or Client. Generates one or more Deliveries. Contains a snapshot of client info at the time of creation (denormalized) for invoice record integrity.

| Column          | Type          | Constraints                    | Description                           |
|-----------------|---------------|--------------------------------|---------------------------------------|
| id              | SERIAL        | PK                             | Invoice identifier                    |
| client_id       | INTEGER       | NULL, FK                       | References Client.id (SET NULL)       |
| processed_by_id | INTEGER       | NULL, FK                       | References Employee.id (SET NULL)     |
| warehouse_id    | INTEGER       | NULL, FK                       | References Warehouse.id (SET NULL)    |
| invoice_status  | VARCHAR(30)   | NOT NULL, DEFAULT 'Pending'    | Current status                        |
| invoice_type    | VARCHAR(50)   | DEFAULT ''                     | Type (Paid_on_Send, Paid_On_Delivery) |
| quantity        | INTEGER       | NULL                           | Number of items/services              |
| invoice_datetime| TIMESTAMPTZ   | NULL                           | When transaction occurred             |
| cost            | DECIMAL(10,2) | NULL                           | Total cost (auto-calculated by trigger)|
| subtotal        | DECIMAL(10,2) | NULL                           | Sum of items before tax               |
| tax_amount      | DECIMAL(10,2) | NULL                           | Calculated tax (23%)                  |
| paid            | BOOLEAN       | NOT NULL, DEFAULT FALSE        | Whether payment received              |
| payment_method  | VARCHAR(50)   | DEFAULT ''                     | Payment method (Cash, Card, etc)      |
| name            | VARCHAR(100)  | DEFAULT ''                     | Client name snapshot                  |
| address         | VARCHAR(200)  | DEFAULT ''                     | Client address snapshot               |
| contact         | VARCHAR(50)   | DEFAULT ''                     | Client contact snapshot               |
| created_at      | TIMESTAMPTZ   | NOT NULL, DEFAULT NOW()        | Record creation timestamp             |
| updated_at      | TIMESTAMPTZ   | NOT NULL, DEFAULT NOW()        | Last update timestamp                 |

**CHECK:** `invoice_status IN ('Pending', 'Confirmed', 'Paid', 'Cancelled', 'Refunded')`, `cost IS NULL OR cost >= 0`

**Triggers:** `trg_invoice_update_cost` recalculates cost when InvoiceItems change. `fn_validate_invoice` sets status to 'Paid' when paid=TRUE.

---

## INVOICE_ITEM
**Purpose:** Individual line items within an Invoice. Each item represents a shipment with specific weight, speed, and pricing. The item total (`quantity * unit_price`) is calculated on-the-fly in queries, not stored as a column.

| Column         | Type          | Constraints                  | Description                       |
|----------------|---------------|------------------------------|-----------------------------------|
| id_item        | SERIAL        | PK                           | Item identifier                   |
| invoice_id     | INTEGER       | NOT NULL, FK                 | References Invoice.id (CASCADE)   |
| shipment_type  | VARCHAR(50)   | NOT NULL                     | Type of shipment                  |
| weight         | DECIMAL(10,2) | NOT NULL                     | Package weight                    |
| delivery_speed | VARCHAR(50)   | NOT NULL                     | Speed tier                        |
| quantity       | INTEGER       | NOT NULL, DEFAULT 1          | Number of identical items         |
| unit_price     | DECIMAL(10,2) | NOT NULL                     | Price per unit                    |
| notes          | TEXT          | DEFAULT ''                   | Additional notes                  |
| created_at     | TIMESTAMPTZ   | NOT NULL, DEFAULT NOW()      | Record creation timestamp         |
| updated_at     | TIMESTAMPTZ   | NOT NULL, DEFAULT NOW()      | Last update timestamp             |

**CHECK:** `quantity > 0`, `unit_price >= 0`, `weight > 0`, `delivery_speed IN ('Standard', 'Express', 'Overnight', 'Economy')`

---

## ROUTE
**Purpose:** Represents a driver's journey from a Warehouse. A Route uses one Vehicle, is driven by one Driver, departs from one Warehouse (origin), and carries multiple Deliveries. Does NOT store origin/destination addresses — origin is derived from the Warehouse FK, and destinations are the recipient addresses of the assigned Deliveries.

| Column              | Type          | Constraints                    | Description                        |
|---------------------|---------------|--------------------------------|------------------------------------|
| id                  | SERIAL        | PK                             | Route identifier                   |
| driver_id           | INTEGER       | NULL, FK                       | References Employee.id (SET NULL)  |
| vehicle_id          | INTEGER       | NULL, FK                       | References Vehicle.id (SET NULL)   |
| warehouse_id        | INTEGER       | NULL, FK                       | References Warehouse.id (SET NULL) — origin |
| description         | TEXT          | NOT NULL                       | Route description / area covered   |
| delivery_status     | VARCHAR(50)   | NOT NULL, DEFAULT 'Scheduled'  | Current status                     |
| delivery_date       | DATE          | NULL                           | Scheduled date                     |
| delivery_start_time | TIME          | NULL                           | Planned start time                 |
| delivery_end_time   | TIME          | NULL                           | Planned end time                   |
| expected_duration   | INTERVAL      | NULL                           | Expected duration                  |
| kms_travelled       | DECIMAL(10,2) | NOT NULL, DEFAULT 0            | Distance covered                   |
| driver_notes        | TEXT          | DEFAULT ''                     | Driver observations                |
| is_active           | BOOLEAN       | NOT NULL, DEFAULT TRUE         | Whether route is active            |
| created_at          | TIMESTAMPTZ   | NOT NULL, DEFAULT NOW()        | Record creation timestamp          |
| updated_at          | TIMESTAMPTZ   | NOT NULL, DEFAULT NOW()        | Last update timestamp              |

**CHECK:** `delivery_status IN ('Scheduled', 'InProgress', 'Completed', 'Cancelled')`, `kms_travelled >= 0`, `end_time > start_time`

**UNIQUE:** `(driver_id, vehicle_id, delivery_date)` — prevents double-booking.

**Trigger:** `trg_route_completed` — when Route status changes to 'Completed', all assigned Deliveries are also marked 'Completed'.

---

## DELIVERY
**Purpose:** Each individual package to be delivered. The central entity for package tracking. Created automatically from an Invoice or manually by Admin. Assigned to a Route for transport. Contains flattened sender/recipient info (snapshots, not FKs) because sender/recipient may not be registered users.

| Column            | Type          | Constraints                      | Description                           |
|-------------------|---------------|----------------------------------|---------------------------------------|
| id                | SERIAL        | PK                               | Delivery identifier                   |
| invoice_id        | INTEGER       | NULL, FK                         | References Invoice.id (SET NULL)      |
| driver_id         | INTEGER       | NULL, FK                         | References Employee.id (SET NULL) — denormalized convenience |
| client_id         | INTEGER       | NULL, FK                         | References Client.id (SET NULL)       |
| route_id          | INTEGER       | NULL, FK                         | References Route.id (SET NULL)        |
| warehouse_id      | INTEGER       | NULL, FK                         | References Warehouse.id (SET NULL)    |
| tracking_number   | VARCHAR(50)   | NOT NULL, UNIQUE                 | Unique tracking code for clients      |
| description       | TEXT          | DEFAULT ''                       | Special instructions                  |
| sender_name       | VARCHAR(100)  | NOT NULL                         | Sender full name (snapshot)           |
| sender_address    | VARCHAR(255)  | NOT NULL                         | Sender address (snapshot)             |
| sender_phone      | VARCHAR(50)   | DEFAULT ''                       | Sender phone                          |
| sender_email      | VARCHAR(254)  | DEFAULT ''                       | Sender email                          |
| recipient_name    | VARCHAR(100)  | NOT NULL                         | Recipient full name (snapshot)        |
| recipient_address | VARCHAR(255)  | NOT NULL                         | Recipient address (= destination)     |
| recipient_phone   | VARCHAR(50)   | DEFAULT ''                       | Recipient phone                       |
| recipient_email   | VARCHAR(254)  | DEFAULT ''                       | Recipient email                       |
| item_type         | VARCHAR(50)   | NOT NULL                         | Package type                          |
| weight            | DECIMAL(10,2) | NOT NULL                         | Weight in grams                       |
| dimensions        | VARCHAR(100)  | DEFAULT ''                       | Package dimensions (e.g. "30x20x15") |
| status            | VARCHAR(20)   | NOT NULL, DEFAULT 'Registered'   | Current status (snapshot)             |
| priority          | VARCHAR(10)   | NOT NULL, DEFAULT 'normal'       | Delivery priority                     |
| updated_at        | TIMESTAMPTZ   | NULL                             | Last update timestamp                 |
| in_transition     | BOOLEAN       | NOT NULL, DEFAULT FALSE          | Whether currently being moved         |
| delivery_date     | DATE          | NULL                             | Actual/scheduled delivery date        |
| is_deleted        | BOOLEAN       | NOT NULL, DEFAULT FALSE          | Soft delete flag                      |
| deleted_at        | TIMESTAMPTZ   | NULL                             | When soft-deleted                     |
| created_at        | TIMESTAMPTZ   | NOT NULL, DEFAULT NOW()          | Record creation timestamp             |

**CHECK:** `status IN ('Registered', 'Ready', 'Pending', 'In Transit', 'Completed', 'Cancelled')`, `priority IN ('normal', 'urgent')`, `weight > 0`

**Tracking:** Query by `tracking_number` for current status. JOIN `delivery_tracking` for full timeline. JOIN Route for driver/vehicle/timing. JOIN Warehouse (via Route) for origin.

---

## DELIVERY_TRACKING
**Purpose:** Append-only event log that records every status change of a Delivery. Provides the full tracking timeline that clients see when they look up a package. Populated automatically by `trg_delivery_tracking_log` trigger whenever a Delivery is inserted or its status changes.

| Column        | Type         | Constraints                  | Description                              |
|---------------|--------------|------------------------------|------------------------------------------|
| id            | SERIAL       | PK                           | Event identifier                         |
| delivery_id   | INTEGER      | NOT NULL, FK                 | References Delivery.id (CASCADE)         |
| changed_by_id | INTEGER      | NULL, FK                     | References Employee.id (SET NULL) — who changed status |
| warehouse_id  | INTEGER      | NULL, FK                     | References Warehouse.id (SET NULL) — location at time of event |
| status        | VARCHAR(20)  | NOT NULL                     | Status at this point in time             |
| notes         | TEXT         | DEFAULT ''                   | Optional notes (e.g. "Delivery attempt failed") |
| created_at    | TIMESTAMPTZ  | NOT NULL, DEFAULT NOW()      | Timestamp of this event                  |

**CHECK:** `status IN ('Registered', 'Ready', 'Pending', 'In Transit', 'Completed', 'Cancelled')`

**Rules:**
- Rows are only INSERT-ed, never UPDATE-d or DELETE-d (append-only)
- Automatically populated by `trg_delivery_tracking_log` trigger
- Also populated via `sp_update_delivery_status()` which sets `changed_by_id` and `warehouse_id` before the trigger fires

**Example timeline for tracking number PT2025010001:**
```
2026-02-06 09:15  Registered     Armazém Central Lisboa    (Staff: João)
2026-02-06 14:00  Ready          Armazém Central Lisboa    (Staff: João)
2026-02-06 14:30  In Transit     -                         (Driver: Pedro)
2026-02-07 10:20  Completed      -                         (Driver: Pedro)
```

---

## NOTIFICATION (MongoDB)
**Purpose:** Notification records stored in MongoDB (not PostgreSQL). Used for sending alerts about system events (deliveries imported, routes created, etc). Accessed via PyMongo, not Django ORM.

| Field              | Type         | Constraints              | Description                              |
|--------------------|--------------|--------------------------|------------------------------------------|
| _id                | ObjectId     | PK (auto)                | MongoDB document identifier              |
| notification_type  | String       | NOT NULL                 | Type (sms, email, push, whatsapp)        |
| recipient_contact  | String       | NOT NULL                 | Phone or email of recipient              |
| subject            | String       | NULLABLE                 | Email subject / notification title       |
| message            | String       | NOT NULL                 | Full notification content                |
| status             | String       | NOT NULL                 | Status (pending, sent, delivered, failed)|
| error_message      | String       | NULLABLE                 | Error details if status=failed           |
| created_at         | Date         | DEFAULT NOW              | When notification was created            |

---

## Entity Count Summary

| Entity             | Columns | FKs | In PostgreSQL | Purpose                          |
|--------------------|---------|-----|---------------|----------------------------------|
| User               | 13      | 0   | Yes           | Base user identity               |
| Client             | 3       | 1   | Yes           | Client-specific data             |
| Employee           | 8       | 2   | Yes           | Employee work info               |
| EmployeeDriver     | 7       | 1   | Yes           | Driver license/status            |
| EmployeeStaff      | 3       | 1   | Yes           | Staff department                 |
| Warehouse          | 11      | 0   | Yes           | Physical locations               |
| Vehicle            | 13      | 0   | Yes           | Fleet management                 |
| Invoice            | 18      | 3   | Yes           | Service billing                  |
| InvoiceItem        | 10      | 1   | Yes           | Invoice line items               |
| Route              | 15      | 3   | Yes           | Driver journeys                  |
| Delivery           | 25      | 5   | Yes           | Package tracking                 |
| DeliveryTracking   | 7       | 3   | Yes           | Status event log                 |
| Notification       | 7       | 0   | No (MongoDB)  | System alerts                    |
