-- Sample data for the refactored Post Office application
--
-- This script inserts basic fixtures into the PostgreSQL database so you can
-- explore the application without using the admin site or the Django ORM.  It
-- creates one user for each role, two employees (driver and staff) and their
-- related driver/staff records, three warehouses, three vehicles, three
-- invoices, two routes and three deliveries.  Adjust IDs or values as
-- required; all foreign keys assume the primary keys shown here.

-- -------------------------------------------------------------------------
-- USERS
-- -------------------------------------------------------------------------
-- The ``password`` fields contain precomputed PBKDF2 hashes for the plain
-- text password ``password123``.  Admin and manager users have ``is_staff``
-- set appropriately; only the admin is a superuser.
INSERT INTO "PostOffice_App_user"
    (id, username, password, first_name, last_name, email, full_name,
     contact, address, tax_id, role,
     is_staff, is_superuser, is_active, date_joined, created_at, updated_at)
VALUES
    (1, 'adminuser',
     'pbkdf2_sha256$260000$d1efc05cb8989bf667cc8cc5ef59fc58$U1d/CEFQ+3q0fs/6zdTZW7ck+VVeCzIbdPCtFnhPkJU=',
     'Admin', 'User', 'admin@example.com', 'Admin User', '912345678',
     'Admin Street', '111111111', 'admin',
     TRUE, TRUE, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    (2, 'clientuser',
     'pbkdf2_sha256$260000$ddec894eb0962f566dea445f26c08d2a$uBUdpYyeB/zHMZh16IzYE3YaMdyUgBsAFbxPFlX9Ihc=',
     'Client', 'User', 'client@example.com', 'Client User', '912345679',
     'Client Street', '222222222', 'client',
     FALSE, FALSE, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    (3, 'driveruser',
     'pbkdf2_sha256$260000$b90027de35d054c47a06b17265c13d85$5eXZjE9TKhF6QuB/aBz709wfwa/Ql39fgmhEbT9a/H8=',
     'Driver', 'User', 'driver@example.com', 'Driver User', '912345680',
     'Driver Street', '333333333', 'driver',
     FALSE, FALSE, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    (4, 'staffuser',
     'pbkdf2_sha256$260000$e1209424fb48a7e3b1632a913b157e74$N0ImlO46O1ExY+dC2YyqrBy/QNjV6nzcVdgmFQyx0sQ=',
     'Staff', 'User', 'staff@example.com', 'Staff User', '912345681',
     'Staff Street', '444444444', 'staff',
     FALSE, FALSE, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    (5, 'manageruser',
     'pbkdf2_sha256$260000$525349438fc22cc89959166ad21afd3a$eGuHuyvcuR319Ln/saf/SOsGfar0c/ApyP7cGkXNd5o=',
     'Manager', 'User', 'manager@example.com', 'Manager User', '912345682',
     'Manager Street', '555555555', 'manager',
     TRUE, FALSE, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- -------------------------------------------------------------------------
-- EMPLOYEES AND RELATED DRIVER/STAFF INFO
-- -------------------------------------------------------------------------
-- Only users with the ``driver`` and ``staff`` roles are given Employee
-- records.  The ``employee_id`` values here correspond to the IDs created
-- in this block (1 for the driver, 2 for the staff).
INSERT INTO "PostOffice_App_employee"
    (id, user_id, position, schedule, wage, is_active, hire_date)
VALUES
    (1, 3, 'Driver', '08:00-16:00', 1500.00, TRUE, '2024-01-15'),
    (2, 4, 'Staff',  '09:00-17:00', 1200.00, TRUE, '2023-11-20');

-- Driver-specific details
INSERT INTO "PostOffice_App_employeedriver"
    (id, employee_id, license_number, license_category, license_expiry_date,
     driving_experience_years, driver_status)
VALUES
    (1, 1, 'DRV123456', 'B', '2026-12-31', 5, 'Available');

-- Staff-specific details
INSERT INTO "PostOffice_App_employeestaff"
    (id, employee_id, department)
VALUES
    (1, 2, 'Customer Service');

-- -------------------------------------------------------------------------
-- WAREHOUSES
-- -------------------------------------------------------------------------
INSERT INTO "PostOffice_App_warehouse"
    (id, name, address, contact, po_schedule_open, po_schedule_close,
     maximum_storage_capacity)
VALUES
    (1, 'Central Warehouse', '123 Main St', '123456789', '08:00:00', '18:00:00', 500),
    (2, 'West Side Depot', '456 West St', '987654321', '09:00:00', '17:00:00', 300),
    (3, 'East End Storage', '789 East Ave', '555666777', '07:30:00', '19:00:00', 400);

-- -------------------------------------------------------------------------
-- VEHICLES
-- -------------------------------------------------------------------------
INSERT INTO "PostOffice_App_vehicle"
    (id, vehicle_type, plate_number, capacity, brand, model, vehicle_status,
     year, fuel_type, last_maintenance_date)
VALUES
    (1, 'Van',   'AA-11-BB', 1200.0, 'Ford',     'Transit', 'Available', 2020, 'Diesel',  '2024-06-01'),
    (2, 'Truck', 'CC-22-DD', 5000.0, 'Mercedes', 'Actros',  'In Service', 2019, 'Diesel',  '2024-05-15'),
    (3, 'Car',   'EE-33-FF',  500.0, 'Renault',  'Kangoo',  'Available', 2021, 'Electric', '2024-04-20');

-- -------------------------------------------------------------------------
-- INVOICES
-- -------------------------------------------------------------------------
INSERT INTO "PostOffice_App_invoice"
    (id_invoice, user_id, invoice_status, invoice_type, quantity,
     invoice_datetime, cost, paid, payment_method, name, address, contact)
VALUES
    (1, 2, 'Issued', 'Standard', 2, CURRENT_TIMESTAMP, 100.50, FALSE, 'Credit Card', 'Client User', 'Client Street', '912345679'),
    (2, 2, 'Paid',   'Premium',  1, CURRENT_TIMESTAMP, 200.75, TRUE,  'PayPal',      'Client User', 'Client Street', '912345679'),
    (3, NULL, 'Pending','Standard', 3, CURRENT_TIMESTAMP,  50.00, FALSE, 'Cash',       'Walk-in',     'Unknown',       '000000000');

-- -------------------------------------------------------------------------
-- ROUTES
-- -------------------------------------------------------------------------
INSERT INTO "PostOffice_App_route"
    (id, description, delivery_status, delivery_date, delivery_start_time,
     delivery_end_time, expected_duration, kms_travelled, driver_notes,
     driver_id, vehicle_id, origin_name, origin_address, origin_contact,
     destination_name, destination_address, destination_contact)
VALUES
    (1, 'Morning deliveries route', 'In Transit', CURRENT_DATE,
     '09:00:00', '12:00:00', '03:00:00', 45.0, '' ,
     1, 1,
     'Central Warehouse', '123 Main St', '123456789',
     'Client A', 'Av. das Figueiras', '912333444'),
    (2, 'Afternoon deliveries route', 'Pending', CURRENT_DATE + INTERVAL '1 day',
     '14:00:00', '17:00:00', '03:00:00', 60.0, '',
     1, 2,
     'West Side Depot', '456 West St', '987654321',
     'Client B', 'Rua do Souto', '912555666');

-- -------------------------------------------------------------------------
-- DELIVERIES
-- -------------------------------------------------------------------------
INSERT INTO "PostOffice_App_delivery"
    (id, invoice_id, tracking_number, description, sender_name, sender_address,
     sender_phone, sender_email, recipient_name, recipient_address, recipient_phone,
     recipient_email, item_type, weight, dimensions, status, priority,
     registered_at, updated_at, in_transition, destination, delivery_date,
     driver_id, client_id, route_id)
VALUES
    (1, 1, 'TRK123456', 'Books', 'Alice', 'Rua A', '912111111', 'alice@example.com',
     'Client A', 'Av. das Figueiras', '912222222', 'clienta@example.com',
     'Package', 1500, '30x20x15', 'In Transit', 'normal',
     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, TRUE, 'Client A address', CURRENT_DATE, 1, 2, 1),
    (2, 2, 'TRK654321', 'Electronics', 'Bob', 'Rua B', '912333333', 'bob@example.com',
     'Client B', 'Rua do Souto', '912444444', 'clientb@example.com',
     'Box', 500, '40x30x20', 'Pending', 'urgent',
     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, FALSE, 'Client B address', CURRENT_DATE + INTERVAL '1 day', 1, 2, 2),
    (3, 3, 'TRK789012', 'Clothes', 'Charlie', 'Rua C', '912555555', 'charlie@example.com',
     'Client C', 'Rua das Flores', '912666666', 'clientc@example.com',
     'Parcel', 800, '25x25x10', 'Registered', 'normal',
     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, FALSE, 'Client C address', NULL, 1, NULL, NULL);

-- -------------------------------------------------------------------------
-- Reset sequences (optional)
-- -------------------------------------------------------------------------
-- After inserting explicit primary keys, update the associated sequences so
-- that future inserts with default values do not collide.  Uncomment the
-- following lines if you plan to continue inserting via Django or SQL without
-- specifying IDs.
-- SELECT setval(pg_get_serial_sequence('"PostOffice_App_user"','id'), (SELECT MAX(id) FROM "PostOffice_App_user"));
-- SELECT setval(pg_get_serial_sequence('"PostOffice_App_employee"','id'), (SELECT MAX(id) FROM "PostOffice_App_employee"));
-- SELECT setval(pg_get_serial_sequence('"PostOffice_App_employeedriver"','id'), (SELECT MAX(id) FROM "PostOffice_App_employeedriver"));
-- SELECT setval(pg_get_serial_sequence('"PostOffice_App_employeestaff"','id'), (SELECT MAX(id) FROM "PostOffice_App_employeestaff"));
-- SELECT setval(pg_get_serial_sequence('"PostOffice_App_warehouse"','id'), (SELECT MAX(id) FROM "PostOffice_App_warehouse"));
-- SELECT setval(pg_get_serial_sequence('"PostOffice_App_vehicle"','id'), (SELECT MAX(id) FROM "PostOffice_App_vehicle"));
-- SELECT setval(pg_get_serial_sequence('"PostOffice_App_invoice"','id_invoice'), (SELECT MAX(id_invoice) FROM "PostOffice_App_invoice"));
-- SELECT setval(pg_get_serial_sequence('"PostOffice_App_route"','id'), (SELECT MAX(id) FROM "PostOffice_App_route"));
-- SELECT setval(pg_get_serial_sequence('"PostOffice_App_delivery"','id'), (SELECT MAX(id) FROM "PostOffice_App_delivery"));