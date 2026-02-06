--   ┌────────────────┬────────────┬──────────────────────────────────────────────────────────┐
--   │     Tabela     │     PK     │                           FKs                            │
--   ├────────────────┼────────────┼──────────────────────────────────────────────────────────┤
--   │ User           │ id         │ -                                                        │
--   ├────────────────┼────────────┼──────────────────────────────────────────────────────────┤
--   │ Client         │ id         │ user_id                                                  │
--   ├────────────────┼────────────┼──────────────────────────────────────────────────────────┤
--   │ Warehouse      │ id         │ -                                                        │
--   ├────────────────┼────────────┼──────────────────────────────────────────────────────────┤
--   │ Employee       │ id         │ user_id, warehouse_id                                    │
--   ├────────────────┼────────────┼──────────────────────────────────────────────────────────┤
--   │ EmployeeDriver │ id         │ employee_id                                              │
--   ├────────────────┼────────────┼──────────────────────────────────────────────────────────┤
--   │ EmployeeStaff  │ id         │ employee_id                                              │
--   ├────────────────┼────────────┼──────────────────────────────────────────────────────────┤
--   │ Vehicle        │ id         │ -                                                        │
--   ├────────────────┼────────────┼──────────────────────────────────────────────────────────┤
--   │ Invoice        │ id_invoice │ client_id, processed_by_id, warehouse_id                 │
--   ├────────────────┼────────────┼──────────────────────────────────────────────────────────┤
--   │ InvoiceItem    │ id_item    │ invoice_id                                               │
--   ├────────────────┼────────────┼──────────────────────────────────────────────────────────┤
--   │ Route          │ id         │ driver_id, vehicle_id, warehouse_id                      │
--   ├────────────────┼────────────┼──────────────────────────────────────────────────────────┤
--   │ Delivery       │ id         │ invoice_id, driver_id, client_id, route_id, warehouse_id │
--   ├────────────────┼────────────┼──────────────────────────────────────────────────────────┤
--   │ DeliveryTrack. │ id         │ delivery_id, changed_by_id, warehouse_id                 │
--   └────────────────┴────────────┴──────────────────────────────────────────────────────────┘
--
/*==============================================================*/
/* DBMS name:      PostgreSQL 14+                              */
/* Project:        PostOffice - Django Compatible DDL          */
/* Created on:     05/02/2026                                  */
/* Description:    Schema aligned with Django models.py        */
/*                 Supports stored procedures, triggers,       */
/*                 views, and materialized views               */
/*                                                             */
/* INHERITANCE STRUCTURE:                                      */
/*   User (base)                                               */
/*     ├── Client (exclusive) - id_client                      */
/*     └── Employee (exclusive) - id_employee                  */
/*           ├── EmployeeDriver (exclusive) - id_driver        */
/*           └── EmployeeStaff (exclusive) - id_staff          */
/*                                                             */
/* EXCLUSIVITY RULES:                                          */
/*   - A User can be Client OR Employee, never both            */
/*   - An Employee can be Driver OR Staff, never both          */
/*   - Admins/Managers are Users without Client/Employee       */
/*==============================================================*/

/*==============================================================*/
/* DROP EXISTING OBJECTS (in reverse dependency order)         */
/*==============================================================*/

-- Drop indexes
DROP INDEX IF EXISTS idx_delivery_tracking_number;
DROP INDEX IF EXISTS idx_delivery_status;
DROP INDEX IF EXISTS idx_delivery_client;
DROP INDEX IF EXISTS idx_delivery_driver;
DROP INDEX IF EXISTS idx_delivery_route;
DROP INDEX IF EXISTS idx_delivery_invoice;
DROP INDEX IF EXISTS idx_route_driver;
DROP INDEX IF EXISTS idx_route_vehicle;
DROP INDEX IF EXISTS idx_route_delivery_date;
DROP INDEX IF EXISTS idx_invoice_client;
DROP INDEX IF EXISTS idx_invoice_status;
DROP INDEX IF EXISTS idx_invoice_item_invoice;
DROP INDEX IF EXISTS idx_employee_user;
DROP INDEX IF EXISTS idx_employee_warehouse;
DROP INDEX IF EXISTS idx_employee_driver_employee;
DROP INDEX IF EXISTS idx_employee_staff_employee;
DROP INDEX IF EXISTS idx_client_user;
DROP INDEX IF EXISTS idx_user_role;
DROP INDEX IF EXISTS idx_user_email;

-- Drop tables (in reverse dependency order)
DROP TABLE IF EXISTS postoffice_app_delivery_tracking CASCADE;
DROP TABLE IF EXISTS postoffice_app_delivery CASCADE;
DROP TABLE IF EXISTS postoffice_app_route CASCADE;
DROP TABLE IF EXISTS postoffice_app_invoiceitem CASCADE;
DROP TABLE IF EXISTS postoffice_app_invoice CASCADE;
DROP TABLE IF EXISTS postoffice_app_vehicle CASCADE;
DROP TABLE IF EXISTS postoffice_app_employeedriver CASCADE;
DROP TABLE IF EXISTS postoffice_app_employeestaff CASCADE;
DROP TABLE IF EXISTS postoffice_app_employee CASCADE;
DROP TABLE IF EXISTS postoffice_app_client CASCADE;
DROP TABLE IF EXISTS postoffice_app_warehouse CASCADE;
DROP TABLE IF EXISTS postoffice_app_user CASCADE;


-- # USER: Contains common attributes shared by all user types
-- base table for all system users
-- Admins/Managers are ONLY in this table
CREATE TABLE postoffice_app_user (
    id                  SERIAL          PRIMARY KEY,

    -- Django AbstractUser required fields
    password            VARCHAR(128)    NOT NULL,
    is_superuser        BOOLEAN         NOT NULL DEFAULT FALSE, -- Django flag for superuser/admin privileges
    username            VARCHAR(150)    NOT NULL UNIQUE,
    first_name          VARCHAR(150)    NOT NULL DEFAULT '',
    last_name           VARCHAR(150)    NOT NULL DEFAULT '',
    email               VARCHAR(254)    NOT NULL DEFAULT '',
    is_staff            BOOLEAN         NOT NULL DEFAULT FALSE,

    -- Custom fields (common to all users)
    contact             VARCHAR(50)     DEFAULT '',
    address             VARCHAR(255)    DEFAULT '',
    role                VARCHAR(20)     NOT NULL DEFAULT 'client',
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT chk_user_role CHECK (role IN ('admin', 'client', 'driver', 'staff', 'manager'))
);


-- # CLIENT: are users who request delivery services
-- EXCLUSIVE with EMPLOYEE
-- client.id - distinct from user_id, used for business identification
-- tax_id for invoicing purposes - may differ from personal ID
CREATE TABLE postoffice_app_client (
    id                  SERIAL          PRIMARY KEY,
    user_id             INTEGER         NOT NULL UNIQUE,
    tax_id              VARCHAR(50)     DEFAULT '', -- Client specific field: NIF for invoicing (can differ from personal)

    -- Foreign Keys
    CONSTRAINT fk_client_user
        FOREIGN KEY (user_id)
        REFERENCES postoffice_app_user(id)
        ON DELETE CASCADE
);

-- # EMPLOYEE: are users who work at the post office
-- EXCLUSIVE with CLIENT
-- Has its own id_employee for HR identification
CREATE TABLE postoffice_app_employee (
    id                  SERIAL          PRIMARY KEY,
    user_id             INTEGER         NOT NULL UNIQUE,
    warehouse_id        INTEGER         NULL,

    position            VARCHAR(20)     NOT NULL,  -- DRIVER || STAFF
    schedule            VARCHAR(50)     DEFAULT '',
    wage                DECIMAL(8,2)    NOT NULL DEFAULT 0.00,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    hire_date           DATE            NULL,

    -- Constraints
    CONSTRAINT chk_employee_position CHECK (position IN ('Driver', 'Staff')),
    CONSTRAINT chk_employee_wage CHECK (wage >= 0),

    -- Foreign Keys
    CONSTRAINT fk_employee_user
        FOREIGN KEY (user_id)
        REFERENCES postoffice_app_user(id)
        ON DELETE CASCADE,
    CONSTRAINT fk_employee_warehouse
        FOREIGN KEY (warehouse_id)
        REFERENCES postoffice_app_warehouse(id)
        ON DELETE SET NULL
);

-- # EMPLOYEE_DRIVER
-- EXCLUSIVE with EmployeeStaff
-- employeedriver.id: for driver-specific identification
CREATE TABLE postoffice_app_employeedriver (
    id                          SERIAL          PRIMARY KEY,
    employee_id                 INTEGER         NOT NULL UNIQUE,

    license_number              VARCHAR(50)     NOT NULL,
    license_category            VARCHAR(10)     NOT NULL,
    license_expiry_date         DATE            NOT NULL,
    driving_experience_years    INTEGER         NOT NULL DEFAULT 0,
    driver_status               VARCHAR(50)     NOT NULL DEFAULT 'Available', -- Available/OnDuty/OffDuty/OnLeave

    -- Constraints
    CONSTRAINT chk_driver_experience CHECK (driving_experience_years >= 0),
    CONSTRAINT chk_driver_status CHECK (driver_status IN ('Available', 'OnDuty', 'OffDuty', 'OnLeave')),

    -- Foreign Keys
    CONSTRAINT fk_employeedriver_employee
        FOREIGN KEY (employee_id)
        REFERENCES postoffice_app_employee(id)
        ON DELETE CASCADE
);


-- # EMPLOYEE_STAFF
-- EXCLUSIVE with EmployeeDriver
-- employeestaff.id: for staff-specific identification
CREATE TABLE postoffice_app_employeestaff (
    id                  SERIAL          PRIMARY KEY,
    employee_id         INTEGER         NOT NULL UNIQUE,

    department          VARCHAR(32)    NOT NULL,

    -- Foreign Keys
    CONSTRAINT fk_employeestaff_employee
        FOREIGN KEY (employee_id)
        REFERENCES postoffice_app_employee(id)
        ON DELETE CASCADE
);


--      WAREHOUSE: Post office store/warehouse locations
CREATE TABLE postoffice_app_warehouse (
    id                      SERIAL          PRIMARY KEY,
    name                    VARCHAR(100)    NOT NULL,
    address                 VARCHAR(200)    NOT NULL,
    contact                 VARCHAR(50)     NOT NULL,
    schedule_open        TIME            NOT NULL,
    schedule_close       TIME            NOT NULL,
    schedule             TEXT            NOT NULL,
    maximum_storage_capacity INTEGER        NOT NULL,

    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT chk_warehouse_capacity CHECK (maximum_storage_capacity > 0),
    CONSTRAINT chk_warehouse_schedule CHECK (schedule_close > schedule_open)
);


-- # VEHICLE: Fleet vehicles for deliveries
CREATE TABLE postoffice_app_vehicle (
    id                      SERIAL          PRIMARY KEY,

    vehicle_type            VARCHAR(100)    NOT NULL,
    plate_number            VARCHAR(20)     NOT NULL UNIQUE,
    capacity                DECIMAL(10,2)   NOT NULL,
    brand                   VARCHAR(100)    NOT NULL,
    model                   VARCHAR(100)    NOT NULL,
    vehicle_status          VARCHAR(50)     NOT NULL DEFAULT 'Available', -- Available/InUse/Maintenance/Retired
    year                    INTEGER         NOT NULL,
    fuel_type               VARCHAR(50)     NOT NULL,
    last_maintenance_date   DATE            NOT NULL,

    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT chk_vehicle_capacity CHECK (capacity > 0),
    CONSTRAINT chk_vehicle_year CHECK (year BETWEEN 1900 AND 2100),
    CONSTRAINT chk_vehicle_status CHECK (vehicle_status IN ('Available', 'InUse', 'Maintenance', 'Retired'))
);

COMMENT ON TABLE postoffice_app_vehicle IS 'Fleet vehicles for deliveries';


-- # INVOICE: Invoices for delivery services
-- References CLIENT table (id_client), not User directly - ensures only clients can have invoices
CREATE TABLE postoffice_app_invoice (
    id          SERIAL          PRIMARY KEY,
    client_id           INTEGER         NULL,           -- References CLIENT table
    processed_by_id     INTEGER         NULL,           -- Employee who processed
    warehouse_id        INTEGER         NULL,           -- Where invoice was created

    invoice_status      VARCHAR(30)     NOT NULL DEFAULT 'Pending',
    invoice_type        VARCHAR(50)     DEFAULT '',
    quantity            INTEGER         NULL,
    invoice_datetime    TIMESTAMPTZ     NULL,
    cost                DECIMAL(10,2)   NULL,           -- Total (auto-calculated)
    subtotal            DECIMAL(10,2)   NULL,           -- Sum of items (before tax)
    tax_amount          DECIMAL(10,2)   NULL,           -- Calculated tax (23%)
    paid                BOOLEAN         NOT NULL DEFAULT FALSE,
    payment_method      VARCHAR(50)     DEFAULT '',

    -- Client info snapshot (denormalized for invoice record)
    name                VARCHAR(100)    DEFAULT '',
    address             VARCHAR(200)    DEFAULT '',
    contact             VARCHAR(50)     DEFAULT '',

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT chk_invoice_status CHECK (invoice_status IN ('Pending', 'Confirmed', 'Paid', 'Cancelled', 'Refunded')),
    CONSTRAINT chk_invoice_cost CHECK (cost IS NULL OR cost >= 0),

    -- Foreign Keys (client_id now references CLIENT, not USER)
    CONSTRAINT fk_invoice_client
        FOREIGN KEY (client_id)
        REFERENCES postoffice_app_client(id)
        ON DELETE SET NULL,
    CONSTRAINT fk_invoice_processed_by
        FOREIGN KEY (processed_by_id)
        REFERENCES postoffice_app_employee(id)
        ON DELETE SET NULL,
    CONSTRAINT fk_invoice_warehouse
        FOREIGN KEY (warehouse_id)
        REFERENCES postoffice_app_warehouse(id)
        ON DELETE SET NULL
);

-- # INVOICE_ITEM: Line items for invoices
CREATE TABLE postoffice_app_invoiceitem (
    id_item             SERIAL          PRIMARY KEY,
    invoice_id          INTEGER         NOT NULL,

    shipment_type       VARCHAR(50)     NOT NULL,
    weight              DECIMAL(10,2)   NOT NULL,
    delivery_speed      VARCHAR(50)     NOT NULL,
    quantity            INTEGER         NOT NULL DEFAULT 1,
    unit_price          DECIMAL(10,2)   NOT NULL,
    notes               TEXT            DEFAULT '',

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT chk_invoiceitem_quantity CHECK (quantity > 0),
    CONSTRAINT chk_invoiceitem_unit_price CHECK (unit_price >= 0),
    CONSTRAINT chk_invoiceitem_weight CHECK (weight > 0),
    CONSTRAINT chk_invoiceitem_delivery_speed CHECK (delivery_speed IN ('Standard', 'Express', 'Overnight', 'Economy')),

    -- Foreign Keys
    CONSTRAINT fk_invoiceitem_invoice
        FOREIGN KEY (invoice_id)
        REFERENCES postoffice_app_invoice(id_invoice)
        ON DELETE CASCADE
);



-- # ROUTE: Delivery routes with driver, vehicle, and timing information
CREATE TABLE postoffice_app_route (
    id                      SERIAL          PRIMARY KEY,
    driver_id               INTEGER         NULL,       -- Employee (must have position=Driver)
    vehicle_id              INTEGER         NULL,
    warehouse_id            INTEGER         NULL,       -- Origin warehouse

    description             TEXT            NOT NULL,
    delivery_status         VARCHAR(50)     NOT NULL DEFAULT 'Scheduled',

    -- Timing
    delivery_date           DATE            NULL,
    delivery_start_time     TIME            NULL,
    delivery_end_time       TIME            NULL,
    expected_duration       INTERVAL        NULL,

    -- Metrics
    kms_travelled           DECIMAL(10,2)   NOT NULL DEFAULT 0,
    driver_notes            TEXT            DEFAULT '',

    -- Origin is derived from warehouse_id FK (warehouse has name, address, contact)
    -- Destinations are the recipient_address of each delivery assigned to this route

    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT chk_route_status CHECK (delivery_status IN ('Scheduled', 'InProgress', 'Completed', 'Cancelled')),
    CONSTRAINT chk_route_kms CHECK (kms_travelled >= 0),
    CONSTRAINT chk_route_times CHECK (delivery_end_time IS NULL OR delivery_start_time IS NULL OR delivery_end_time > delivery_start_time),

    -- Unique constraint
    CONSTRAINT uq_route_driver_vehicle_date UNIQUE (driver_id, vehicle_id, delivery_date),

    -- Foreign Keys
    CONSTRAINT fk_route_driver
        FOREIGN KEY (driver_id)
        REFERENCES postoffice_app_employee(id)
        ON DELETE SET NULL,
    CONSTRAINT fk_route_vehicle
        FOREIGN KEY (vehicle_id)
        REFERENCES postoffice_app_vehicle(id)
        ON DELETE SET NULL,
    CONSTRAINT fk_route_warehouse
        FOREIGN KEY (warehouse_id)
        REFERENCES postoffice_app_warehouse(id)
        ON DELETE SET NULL
);

COMMENT ON TABLE postoffice_app_route IS 'Delivery routes with driver, vehicle, and timing information';


/*==============================================================*/
/* Table: postoffice_app_delivery                               */
/* Django: Delivery                                             */
/* Notes: client_id references CLIENT (not User directly)       */
/*==============================================================*/
CREATE TABLE postoffice_app_delivery (
    id                      SERIAL          PRIMARY KEY,

    -- Foreign Keys
    invoice_id              INTEGER         NULL,
    driver_id               INTEGER         NULL,       -- Employee (driver)
    client_id               INTEGER         NULL,       -- References CLIENT table
    route_id                INTEGER         NULL,
    warehouse_id            INTEGER         NULL,       -- Origin warehouse

    tracking_number         VARCHAR(50)     NOT NULL UNIQUE,
    description             TEXT            DEFAULT '',

    -- Sender information
    sender_name             VARCHAR(100)    NOT NULL,
    sender_address          VARCHAR(255)    NOT NULL,
    sender_phone            VARCHAR(50)     DEFAULT '',
    sender_email            VARCHAR(254)    DEFAULT '',

    -- Recipient information
    recipient_name          VARCHAR(100)    NOT NULL,
    recipient_address       VARCHAR(255)    NOT NULL,
    recipient_phone         VARCHAR(50)     DEFAULT '',
    recipient_email         VARCHAR(254)    DEFAULT '',

    -- Package details
    item_type               VARCHAR(50)     NOT NULL,
    weight                  DECIMAL(10,2)   NOT NULL,
    dimensions              VARCHAR(100)    DEFAULT '',

    -- Status and priority
    status                  VARCHAR(20)     NOT NULL DEFAULT 'Registered',
    priority                VARCHAR(10)     NOT NULL DEFAULT 'normal',

    -- Timestamps
    updated_at              TIMESTAMPTZ     NULL,
    in_transition           BOOLEAN         NOT NULL DEFAULT FALSE,

    delivery_date           DATE            NULL,

    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT chk_delivery_status CHECK (status IN ('Registered', 'Ready', 'Pending', 'In Transit', 'Completed', 'Cancelled')),
    CONSTRAINT chk_delivery_priority CHECK (priority IN ('normal', 'urgent')),
    CONSTRAINT chk_delivery_weight CHECK (weight > 0),

    -- Foreign Keys (client_id now references CLIENT, not USER)
    CONSTRAINT fk_delivery_invoice
        FOREIGN KEY (invoice_id)
        REFERENCES postoffice_app_invoice(id_invoice)
        ON DELETE SET NULL,
    CONSTRAINT fk_delivery_driver
        FOREIGN KEY (driver_id)
        REFERENCES postoffice_app_employee(id)
        ON DELETE SET NULL,
    CONSTRAINT fk_delivery_client
        FOREIGN KEY (client_id)
        REFERENCES postoffice_app_client(id)
        ON DELETE SET NULL,
    CONSTRAINT fk_delivery_route
        FOREIGN KEY (route_id)
        REFERENCES postoffice_app_route(id)
        ON DELETE SET NULL,
    CONSTRAINT fk_delivery_warehouse
        FOREIGN KEY (warehouse_id)
        REFERENCES postoffice_app_warehouse(id)
        ON DELETE SET NULL
);

COMMENT ON TABLE postoffice_app_delivery IS 'Package deliveries with sender/recipient information';
COMMENT ON COLUMN postoffice_app_delivery.client_id IS 'References CLIENT table (id_client), not User directly - ensures only clients can request deliveries';
COMMENT ON COLUMN postoffice_app_delivery.is_deleted IS 'Soft delete flag - set by trg_delivery_soft_delete';


/*==============================================================*/
/* Table: postoffice_app_delivery_tracking                      */
/* Django: DeliveryTracking                                     */
/* Notes: Event log for delivery status changes (tracking)      */
/*        Populated automatically by trg_delivery_tracking_log  */
/*==============================================================*/
CREATE TABLE postoffice_app_delivery_tracking (
    id                  SERIAL          PRIMARY KEY,

    -- Foreign Keys
    delivery_id         INTEGER         NOT NULL,
    changed_by_id       INTEGER         NULL,       -- Employee who changed status
    warehouse_id        INTEGER         NULL,       -- Location at time of event

    -- Event data
    status              VARCHAR(20)     NOT NULL,   -- Status at this point in time
    notes               TEXT            DEFAULT '',  -- Optional notes (e.g. "Delivery attempt failed")

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT chk_tracking_status CHECK (status IN ('Registered', 'Ready', 'Pending', 'In Transit', 'Completed', 'Cancelled')),

    -- Foreign Keys
    CONSTRAINT fk_tracking_delivery
        FOREIGN KEY (delivery_id)
        REFERENCES postoffice_app_delivery(id)
        ON DELETE CASCADE,
    CONSTRAINT fk_tracking_changed_by
        FOREIGN KEY (changed_by_id)
        REFERENCES postoffice_app_employee(id)
        ON DELETE SET NULL,
    CONSTRAINT fk_tracking_warehouse
        FOREIGN KEY (warehouse_id)
        REFERENCES postoffice_app_warehouse(id)
        ON DELETE SET NULL
);

COMMENT ON TABLE postoffice_app_delivery_tracking IS 'Event log for delivery status changes - provides full tracking timeline';


/*==============================================================*/
/* INDEXES                                                      */
/*==============================================================*/

-- User indexes
CREATE INDEX idx_user_role ON postoffice_app_user(role);
CREATE INDEX idx_user_email ON postoffice_app_user(email);
CREATE INDEX idx_user_is_active ON postoffice_app_user(is_active);
CREATE INDEX idx_user_is_superuser ON postoffice_app_user(is_superuser);

-- Client indexes
CREATE INDEX idx_client_user ON postoffice_app_client(user_id);
CREATE INDEX idx_client_type ON postoffice_app_client(client_type);
CREATE INDEX idx_client_is_active ON postoffice_app_client(is_active);

-- Employee indexes
CREATE INDEX idx_employee_user ON postoffice_app_employee(user_id);
CREATE INDEX idx_employee_warehouse ON postoffice_app_employee(warehouse_id);
CREATE INDEX idx_employee_position ON postoffice_app_employee(position);
CREATE INDEX idx_employee_is_active ON postoffice_app_employee(is_active);

-- Employee driver/staff indexes
CREATE INDEX idx_employee_driver_employee ON postoffice_app_employeedriver(employee_id);
CREATE INDEX idx_employee_driver_status ON postoffice_app_employeedriver(driver_status);
CREATE INDEX idx_employee_staff_employee ON postoffice_app_employeestaff(employee_id);

-- Vehicle indexes
CREATE INDEX idx_vehicle_status ON postoffice_app_vehicle(vehicle_status);
CREATE INDEX idx_vehicle_is_active ON postoffice_app_vehicle(is_active);

-- Invoice indexes
CREATE INDEX idx_invoice_client ON postoffice_app_invoice(client_id);
CREATE INDEX idx_invoice_status ON postoffice_app_invoice(invoice_status);
CREATE INDEX idx_invoice_datetime ON postoffice_app_invoice(invoice_datetime);
CREATE INDEX idx_invoice_processed_by ON postoffice_app_invoice(processed_by_id);

-- Invoice item indexes
CREATE INDEX idx_invoice_item_invoice ON postoffice_app_invoiceitem(invoice_id);

-- Route indexes
CREATE INDEX idx_route_driver ON postoffice_app_route(driver_id);
CREATE INDEX idx_route_vehicle ON postoffice_app_route(vehicle_id);
CREATE INDEX idx_route_delivery_date ON postoffice_app_route(delivery_date);
CREATE INDEX idx_route_status ON postoffice_app_route(delivery_status);
CREATE INDEX idx_route_warehouse ON postoffice_app_route(warehouse_id);

-- Delivery indexes
CREATE INDEX idx_delivery_tracking_number ON postoffice_app_delivery(tracking_number);
CREATE INDEX idx_delivery_status ON postoffice_app_delivery(status);
CREATE INDEX idx_delivery_client ON postoffice_app_delivery(client_id);
CREATE INDEX idx_delivery_driver ON postoffice_app_delivery(driver_id);
CREATE INDEX idx_delivery_route ON postoffice_app_delivery(route_id);
CREATE INDEX idx_delivery_invoice ON postoffice_app_delivery(invoice_id);
CREATE INDEX idx_delivery_is_deleted ON postoffice_app_delivery(is_deleted);
CREATE INDEX idx_delivery_created_at ON postoffice_app_delivery(created_at);
CREATE INDEX idx_delivery_warehouse ON postoffice_app_delivery(warehouse_id);

-- Delivery tracking indexes
CREATE INDEX idx_tracking_delivery ON postoffice_app_delivery_tracking(delivery_id);
CREATE INDEX idx_tracking_status ON postoffice_app_delivery_tracking(status);
CREATE INDEX idx_tracking_created_at ON postoffice_app_delivery_tracking(created_at);
CREATE INDEX idx_tracking_changed_by ON postoffice_app_delivery_tracking(changed_by_id);


/*==============================================================*/
/* INHERITANCE DIAGRAM                                          */
/*==============================================================*/

/*
                              ┌─────────────────────────────────┐
                              │              USER               │
                              │              (id)               │
                              │                                 │
                              │  username, email, password      │
                              │  full_name, contact, address    │
                              │  role, is_superuser, is_active  │
                              └───────────────┬─────────────────┘
                                              │
                    ┌─────────────────────────┴─────────────────────────┐
                    │                                                   │
                    │              MUTUALLY EXCLUSIVE                   │
                    │                                                   │
                    ▼                                                   ▼
       ┌────────────────────────┐                         ┌────────────────────────┐
       │        CLIENT          │                         │       EMPLOYEE         │
       │         (id)           │                         │          (id)          │
       │      FK: user_id       │                         │      FK: user_id       │
       │                        │                         │                        │
       │  tax_id, client_type   │                         │  position, wage        │
       │  preferred_contact     │                         │  schedule, hire_date   │
       └────────────────────────┘                         └───────────┬────────────┘
                                                                      │
                                              ┌────────────────────────┴────────────────────────┐
                                              │                                                 │
                                              │              MUTUALLY EXCLUSIVE                 │
                                              │                                                 │
                                              ▼                                                 ▼
                                 ┌────────────────────────┐                       ┌────────────────────────┐
                                 │    EMPLOYEE_DRIVER     │                       │    EMPLOYEE_STAFF      │
                                 │          (id)          │                       │          (id)          │
                                 │    FK: employee_id     │                       │    FK: employee_id     │
                                 │                        │                       │                        │
                                 │  license_number        │                       │  department            │
                                 │  license_category      │                       │                        │
                                 │  license_expiry_date   │                       │                        │
                                 │  driver_status         │                       │                        │
                                 └────────────────────────┘                       └────────────────────────┘


    ADMIN/MANAGER: Only exist in USER table (is_superuser=TRUE for admin, role='manager' for manager)
    CLIENT: USER + CLIENT record (role='client')
    DRIVER: USER + EMPLOYEE + EMPLOYEE_DRIVER record (role='driver', position='Driver')
    STAFF:  USER + EMPLOYEE + EMPLOYEE_STAFF record (role='staff', position='Staff')

    EXCLUSIVITY ENFORCEMENT:
    - trg_check_client_employee_exclusivity: Prevents User from having both Client AND Employee
    - trg_check_driver_staff_exclusivity: Prevents Employee from having both Driver AND Staff
*/


/*==============================================================*/
/* TRIGGERS TO CREATE (in separate files)                       */
/*==============================================================*/

/*
EXCLUSIVITY TRIGGERS:
- trg_check_client_employee_exclusivity
  * On INSERT to postoffice_app_client: Check user_id not in postoffice_app_employee
  * On INSERT to postoffice_app_employee: Check user_id not in postoffice_app_client

- trg_check_driver_staff_exclusivity
  * On INSERT to postoffice_app_employeedriver: Check employee_id not in postoffice_app_employeestaff
  * On INSERT to postoffice_app_employeestaff: Check employee_id not in postoffice_app_employeedriver

SYNC TRIGGERS:
- trg_employee_sync_user_role: When Employee is created/updated, sync User.role with Employee.position
- trg_client_sync_user_role: When Client is created, set User.role = 'client'

CALCULATION TRIGGERS:
- trg_invoice_item_calc_total: Calculate InvoiceItem.total_price
- trg_invoice_update_cost: Update Invoice totals when items change

SOFT DELETE TRIGGERS:
- trg_delivery_soft_delete: Set is_deleted instead of hard delete

TRACKING TRIGGERS:
- trg_delivery_tracking_log: On INSERT or UPDATE of delivery.status, insert event into delivery_tracking
  * Captures: delivery_id, new status, timestamp
  * Provides full tracking timeline for clients

VALIDATION TRIGGERS:
- trg_delivery_status_workflow: Validate status transitions
- trg_route_time_check: Validate end_time > start_time
*/


/*==============================================================*/
/* STORED PROCEDURES TO CREATE (in separate files)              */
/*==============================================================*/

/*
USER/CLIENT/EMPLOYEE:
- sp_create_client(user_params, client_params) → Creates User + Client in transaction
- sp_create_employee(user_params, employee_params, driver/staff_params) → Creates User + Employee + Driver/Staff
- sp_update_client, sp_update_employee
- sp_delete_client, sp_delete_employee (soft delete)

BUSINESS OPERATIONS:
- sp_create_delivery, sp_update_delivery, sp_delete_delivery, sp_import_deliveries
- sp_update_delivery_status(delivery_id, new_status, employee_id, warehouse_id, notes) → Updates status + logs tracking event
- sp_create_route, sp_update_route, sp_delete_route, sp_import_routes
- sp_create_vehicle, sp_update_vehicle, sp_delete_vehicle, sp_import_vehicles
- sp_create_warehouse, sp_update_warehouse, sp_delete_warehouse, sp_import_warehouses
- sp_create_invoice, sp_update_invoice, sp_delete_invoice, sp_import_invoices
- sp_add_invoice_item
*/
