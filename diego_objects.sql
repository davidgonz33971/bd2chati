/*==============================================================*/
/* diego_objects.sql                                            */
/* Database Objects: User (5) + Employee (5) +                  */
/*                   EmployeeDriver (2) + EmployeeStaff (1) +   */
/*                   Warehouse (7)                              */
/*                                                = 20 objects  */
/*                                                              */
/* Run order: Execute top-to-bottom in pgAdmin Query Tool.      */
/* All table/column names are unquoted lowercase except "USER". */
/*==============================================================*/


/*==============================================================*/
/* Table of Contents                                            */
/*--------------------------------------------------------------*/
/*  #  | Entity         | Type      | Name                     */
/*-----|----------------|-----------|-------------------------- */
/*  1  | EmplDriver     | Function  | fn_is_license_valid      */
/*  2  | User           | View      | v_clients                */
/*  3  | User           | View      | v_potential_employees    */
/*  4  | Employee       | View      | v_employees_full         */
/*  5  | Warehouse      | View      | v_warehouses_full        */
/*  6  | Warehouse      | View      | v_warehouses_export      */
/*  7  | Employee       | Trigger   | trg_employee_sync_user_role */
/*  8  | Warehouse      | Trigger   | trg_warehouse_schedule_check */
/*  9  | User           | Procedure | sp_create_user           */
/* 10  | User           | Procedure | sp_update_user           */
/* 11  | User           | Procedure | sp_delete_user           */
/* 12  | Employee       | Procedure | sp_create_employee       */
/*     |  (also creates EmployeeDriver / EmployeeStaff rows)   */
/* 13  | Employee       | Procedure | sp_update_employee       */
/* 14  | Employee       | Procedure | sp_delete_employee       */
/* 15  | Warehouse      | Procedure | sp_create_warehouse      */
/* 16  | Warehouse      | Procedure | sp_update_warehouse      */
/* 17  | Warehouse      | Procedure | sp_delete_warehouse      */
/* 18  | Warehouse      | Procedure | sp_import_warehouses     */
/*==============================================================*/
/* Note: EmployeeDriver total=2 counts fn_is_license_valid (1) */
/*       + driver logic inside sp_create_employee (1).          */
/*       EmployeeStaff total=1 counts staff logic inside        */
/*       sp_create_employee (1). Standalone SQL blocks = 18.    */
/*==============================================================*/



/* ============================================================ */
/*                       F U N C T I O N S                      */
/* ============================================================ */


-- 1. fn_is_license_valid  [EmployeeDriver]
-- Check if a driver license has not expired.
CREATE OR REPLACE FUNCTION fn_is_license_valid(p_expiry_date DATE)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN p_expiry_date IS NOT NULL AND p_expiry_date > CURRENT_DATE;
END;
$$;



/* ============================================================ */
/*                          V I E W S                           */
/* ============================================================ */


-- 2. v_clients  [User]
-- All users with role='client', joined with client table for tax_id.
CREATE OR REPLACE VIEW v_clients AS
SELECT
    u.id,
    u.username,
    u.email,
    u.first_name,
    u.last_name,
    u.first_name || ' ' || u.last_name  AS full_name,
    u.contact,
    u.address,
    u.role,
    u.is_active,
    u.created_at,
    u.updated_at,
    c.tax_id
FROM "USER" u
JOIN client c ON c.id = u.id
WHERE u.role = 'client'
ORDER BY u.first_name, u.last_name;


-- 3. v_potential_employees  [User]
-- Users eligible to become employees (not admin/client, not already an employee).
CREATE OR REPLACE VIEW v_potential_employees AS
SELECT
    u.id,
    u.username,
    u.email,
    u.first_name,
    u.last_name,
    u.first_name || ' ' || u.last_name  AS full_name,
    u.contact,
    u.address,
    u.role,
    u.is_active,
    u.created_at
FROM "USER" u
WHERE u.role NOT IN ('admin', 'client')
  AND u.is_active = true
  AND NOT EXISTS (SELECT 1 FROM employee e WHERE e.id = u.id)
ORDER BY u.first_name, u.last_name;


-- 4. v_employees_full  [Employee]
-- Employees joined with user info, driver info, and staff info.
-- All joins use shared-PK (id = id).
CREATE OR REPLACE VIEW v_employees_full AS
SELECT
    e.id,
    e.emp_position,
    e.schedule,
    e.wage,
    e.is_active,
    e.hire_date,
    e.war_id,
    w.name                                  AS warehouse_name,
    u.username,
    u.email,
    u.first_name,
    u.last_name,
    u.first_name || ' ' || u.last_name     AS full_name,
    u.contact,
    u.address,
    u.role,
    -- Driver info (NULL if not driver)
    ed.license_number,
    ed.license_category,
    ed.license_expiry_date,
    ed.driving_experience_years,
    ed.driver_status,
    -- Staff info (NULL if not staff)
    es.department
FROM employee e
JOIN "USER" u               ON u.id  = e.id        -- shared PK
LEFT JOIN employee_driver ed ON ed.id = e.id        -- shared PK
LEFT JOIN employee_staff es  ON es.id = e.id        -- shared PK
LEFT JOIN warehouse w        ON w.id  = e.war_id
WHERE e.is_active = true
ORDER BY u.first_name, u.last_name;


-- 5. v_warehouses_full  [Warehouse]
-- All warehouse data with employee count for list pages.
CREATE OR REPLACE VIEW v_warehouses_full AS
SELECT
    w.id,
    w.name,
    w.contact,
    w.address,
    w.schedule_open,
    w.schedule_close,
    w.schedule,
    w.maximum_storage_capacity,
    w.is_active,
    w.created_at,
    w.updated_at,
    COALESCE(emp_count.cnt, 0)  AS employee_count
FROM warehouse w
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt
    FROM employee e
    WHERE e.war_id = w.id AND e.is_active = true
) emp_count ON true
ORDER BY w.name;


-- 6. v_warehouses_export  [Warehouse]
-- Flat view formatted for JSON/CSV export.
CREATE OR REPLACE VIEW v_warehouses_export AS
SELECT
    w.id,
    w.name,
    w.contact,
    w.address,
    w.schedule_open,
    w.schedule_close,
    w.schedule,
    w.maximum_storage_capacity,
    w.is_active,
    w.created_at,
    w.updated_at
FROM warehouse w
ORDER BY w.id;



/* ============================================================ */
/*                       T R I G G E R S                        */
/* ============================================================ */


-- 7. trg_employee_sync_user_role  [Employee]
-- AFTER INSERT/UPDATE OF emp_position on employee:
-- auto-update "USER".role to match the employee position.
CREATE OR REPLACE FUNCTION fn_sync_employee_user_role()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.emp_position = 'driver' THEN
        UPDATE "USER"
        SET role = 'driver', updated_at = NOW()
        WHERE id = NEW.id;
    ELSIF NEW.emp_position = 'staff' THEN
        UPDATE "USER"
        SET role = 'staff', updated_at = NOW()
        WHERE id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_employee_sync_user_role ON employee;

CREATE TRIGGER trg_employee_sync_user_role
    AFTER INSERT OR UPDATE OF emp_position ON employee
    FOR EACH ROW
    EXECUTE FUNCTION fn_sync_employee_user_role();


-- 8. trg_warehouse_schedule_check  [Warehouse]
-- BEFORE INSERT/UPDATE on warehouse: ensure schedule_close > schedule_open (when both set).
CREATE OR REPLACE FUNCTION fn_trg_warehouse_schedule_check()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.schedule_open IS NOT NULL
       AND NEW.schedule_close IS NOT NULL
       AND NEW.schedule_close <= NEW.schedule_open
    THEN
        RAISE EXCEPTION 'Warehouse close time (%) must be after open time (%)',
            NEW.schedule_close, NEW.schedule_open;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_warehouse_schedule_check ON warehouse;

CREATE TRIGGER trg_warehouse_schedule_check
    BEFORE INSERT OR UPDATE ON warehouse
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_warehouse_schedule_check();



/* ============================================================ */
/*                     P R O C E D U R E S                      */
/* ============================================================ */


/* ---------- USER ---------- */

-- 9. sp_create_user  [User]
-- Create a new user. Password must be pre-hashed by Django (make_password).
-- If role is 'client', also creates the client record.
CREATE OR REPLACE PROCEDURE sp_create_user(
    p_username      VARCHAR(150),
    p_email         VARCHAR(254),
    p_password      VARCHAR(128),
    p_first_name    VARCHAR(150),
    p_last_name     VARCHAR(150),
    p_contact       VARCHAR(20),
    p_address       VARCHAR(255),
    p_role          VARCHAR(20) DEFAULT 'client',
    INOUT p_id      INT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO "USER" (
        username, email, password, first_name, last_name,
        contact, address, role,
        is_superuser, is_staff, is_active, created_at, updated_at
    ) VALUES (
        p_username, p_email, p_password, p_first_name, p_last_name,
        p_contact, p_address, COALESCE(p_role, 'client'),
        FALSE, FALSE, TRUE, NOW(), NOW()
    )
    RETURNING id INTO p_id;

    -- If role is client, create the client record (shared PK)
    IF COALESCE(p_role, 'client') = 'client' THEN
        INSERT INTO client (id, tax_id) VALUES (p_id, NULL);
    END IF;
END;
$$;


-- 10. sp_update_user  [User]
-- Update a user's profile fields. Does NOT update password (use Django for that).
CREATE OR REPLACE PROCEDURE sp_update_user(
    p_id            INT,
    p_email         VARCHAR(254)  DEFAULT NULL,
    p_first_name    VARCHAR(150)  DEFAULT NULL,
    p_last_name     VARCHAR(150)  DEFAULT NULL,
    p_contact       VARCHAR(20)   DEFAULT NULL,
    p_address       VARCHAR(255)  DEFAULT NULL,
    p_role          VARCHAR(20)   DEFAULT NULL,
    p_is_active     BOOL          DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE "USER"
    SET email      = COALESCE(p_email,      email),
        first_name = COALESCE(p_first_name, first_name),
        last_name  = COALESCE(p_last_name,  last_name),
        contact    = COALESCE(p_contact,    contact),
        address    = COALESCE(p_address,    address),
        role       = COALESCE(p_role,       role),
        is_active  = COALESCE(p_is_active,  is_active),
        updated_at = NOW()
    WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User with id % not found', p_id;
    END IF;
END;
$$;


-- 11. sp_delete_user  [User]
-- Soft-delete a user (set is_active = false).
CREATE OR REPLACE PROCEDURE sp_delete_user(p_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE "USER"
    SET is_active  = false,
        updated_at = NOW()
    WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User with id % not found', p_id;
    END IF;
END;
$$;


/* ---------- EMPLOYEE (+ EMPLOYEE_DRIVER + EMPLOYEE_STAFF) ---------- */

-- 12. sp_create_employee  [Employee + EmployeeDriver + EmployeeStaff]
-- Creates USER + EMPLOYEE + driver/staff sub-type in a single atomic transaction.
-- Password must be pre-hashed by Django (make_password).
-- The trigger trg_employee_sync_user_role auto-updates "USER".role after the employee INSERT.
CREATE OR REPLACE PROCEDURE sp_create_employee(
    -- User params (inserted into "USER")
    p_username          VARCHAR(150),
    p_email             VARCHAR(254),
    p_password          VARCHAR(128),
    p_first_name        VARCHAR(150),
    p_last_name         VARCHAR(150),
    p_contact           VARCHAR(20),
    p_address           VARCHAR(255),
    -- Employee params (inserted into employee)
    p_war_id            INT,
    p_emp_position      VARCHAR(32),
    p_schedule          VARCHAR(255),
    p_wage              DECIMAL(10,2),
    p_hire_date         DATE,
    -- Driver params (nullable — only used when emp_position = 'driver')
    p_license_number    VARCHAR(50)   DEFAULT NULL,
    p_license_category  VARCHAR(20)   DEFAULT NULL,
    p_license_expiry    DATE          DEFAULT NULL,
    p_driving_experience INT          DEFAULT NULL,
    p_driver_status     VARCHAR(20)   DEFAULT NULL,
    -- Staff params (nullable — only used when emp_position = 'staff')
    p_department        VARCHAR(32)   DEFAULT NULL,
    -- Output
    INOUT o_user_id     INT           DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Validate position
    IF p_emp_position NOT IN ('driver', 'staff') THEN
        RAISE EXCEPTION 'Invalid position: %. Must be driver or staff', p_emp_position;
    END IF;

    -- Validate driver has required fields
    IF p_emp_position = 'driver' AND (p_license_number IS NULL OR p_license_expiry IS NULL) THEN
        RAISE EXCEPTION 'Driver position requires license_number and license_expiry';
    END IF;

    -- Validate license not expired
    IF p_emp_position = 'driver' AND NOT fn_is_license_valid(p_license_expiry) THEN
        RAISE EXCEPTION 'License expiry date must be in the future';
    END IF;

    -- Validate staff has department
    IF p_emp_position = 'staff' AND p_department IS NULL THEN
        RAISE EXCEPTION 'Staff position requires department';
    END IF;

    -- Validate wage
    IF p_wage < 0 THEN
        RAISE EXCEPTION 'Wage cannot be negative';
    END IF;

    -- 1) Create user in "USER" (role set temporarily; trigger will sync after employee insert)
    INSERT INTO "USER" (
        username, email, password, first_name, last_name,
        contact, address, role,
        is_superuser, is_staff, is_active, created_at, updated_at
    ) VALUES (
        p_username, p_email, p_password, p_first_name, p_last_name,
        p_contact, p_address, 'client',    -- temp role; trigger fixes it
        FALSE, FALSE, TRUE, NOW(), NOW()
    ) RETURNING id INTO o_user_id;

    -- 2) Create employee (shared PK = same id as "USER")
    --    This fires trg_employee_sync_user_role -> updates "USER".role
    INSERT INTO employee (
        id, war_id, emp_position, schedule, wage, is_active, hire_date
    ) VALUES (
        o_user_id, p_war_id, p_emp_position, p_schedule, p_wage, TRUE, p_hire_date
    );

    -- 3) Create driver-specific record (shared PK = same id as employee)
    IF p_emp_position = 'driver' THEN
        INSERT INTO employee_driver (
            id, license_number, license_category,
            license_expiry_date, driving_experience_years, driver_status
        ) VALUES (
            o_user_id, p_license_number, p_license_category,
            p_license_expiry, p_driving_experience,
            COALESCE(p_driver_status, 'available')
        );
    END IF;

    -- 4) Create staff-specific record (shared PK = same id as employee)
    IF p_emp_position = 'staff' THEN
        INSERT INTO employee_staff (
            id, department
        ) VALUES (
            o_user_id, p_department
        );
    END IF;
END;
$$;


-- 13. sp_update_employee  [Employee]
-- Update employee, user, and driver/staff sub-type records.
-- Handles position changes (e.g. driver -> staff) by deleting old sub-type and creating new.
CREATE OR REPLACE PROCEDURE sp_update_employee(
    p_id                 INT,
    -- User fields
    p_email              VARCHAR(254)  DEFAULT NULL,
    p_first_name         VARCHAR(150)  DEFAULT NULL,
    p_last_name          VARCHAR(150)  DEFAULT NULL,
    p_contact            VARCHAR(20)   DEFAULT NULL,
    p_address            VARCHAR(255)  DEFAULT NULL,
    -- Employee fields
    p_war_id             INT           DEFAULT NULL,
    p_emp_position       VARCHAR(32)   DEFAULT NULL,
    p_schedule           VARCHAR(255)  DEFAULT NULL,
    p_wage               DECIMAL(10,2) DEFAULT NULL,
    p_is_active          BOOL          DEFAULT NULL,
    -- Driver fields (if position is/becomes driver)
    p_license_number     VARCHAR(50)   DEFAULT NULL,
    p_license_category   VARCHAR(20)   DEFAULT NULL,
    p_license_expiry     DATE          DEFAULT NULL,
    p_driving_experience INT           DEFAULT NULL,
    p_driver_status      VARCHAR(20)   DEFAULT NULL,
    -- Staff fields (if position is/becomes staff)
    p_department         VARCHAR(32)   DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_position VARCHAR(32);
BEGIN
    -- Get current position
    SELECT emp_position INTO v_current_position FROM employee WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Employee with id % not found', p_id;
    END IF;

    -- Validate wage if provided
    IF p_wage IS NOT NULL AND p_wage < 0 THEN
        RAISE EXCEPTION 'Wage cannot be negative';
    END IF;

    -- Validate license if switching to driver
    IF p_emp_position = 'driver' AND v_current_position != 'driver' THEN
        IF p_license_number IS NULL OR p_license_expiry IS NULL THEN
            RAISE EXCEPTION 'Driver position requires license_number and license_expiry';
        END IF;
        IF NOT fn_is_license_valid(p_license_expiry) THEN
            RAISE EXCEPTION 'License expiry date must be in the future';
        END IF;
    END IF;

    -- Validate department if switching to staff
    IF p_emp_position = 'staff' AND v_current_position != 'staff' AND p_department IS NULL THEN
        RAISE EXCEPTION 'Staff position requires department';
    END IF;

    -- Update user fields
    UPDATE "USER"
    SET email      = COALESCE(p_email,      email),
        first_name = COALESCE(p_first_name, first_name),
        last_name  = COALESCE(p_last_name,  last_name),
        contact    = COALESCE(p_contact,    contact),
        address    = COALESCE(p_address,    address),
        updated_at = NOW()
    WHERE id = p_id;

    -- Update employee fields
    -- The trigger trg_employee_sync_user_role will update "USER".role if emp_position changes
    UPDATE employee
    SET war_id       = COALESCE(p_war_id,       war_id),
        emp_position = COALESCE(p_emp_position, emp_position),
        schedule     = COALESCE(p_schedule,     schedule),
        wage         = COALESCE(p_wage,         wage),
        is_active    = COALESCE(p_is_active,    is_active)
    WHERE id = p_id;

    -- Handle position change: delete old sub-type, create new
    IF p_emp_position IS NOT NULL AND p_emp_position != v_current_position THEN
        -- Remove old sub-type record
        IF v_current_position = 'driver' THEN
            DELETE FROM employee_driver WHERE id = p_id;
        ELSIF v_current_position = 'staff' THEN
            DELETE FROM employee_staff WHERE id = p_id;
        END IF;

        -- Create new sub-type record
        IF p_emp_position = 'driver' THEN
            INSERT INTO employee_driver (
                id, license_number, license_category,
                license_expiry_date, driving_experience_years, driver_status
            ) VALUES (
                p_id, p_license_number, p_license_category,
                p_license_expiry, p_driving_experience,
                COALESCE(p_driver_status, 'available')
            );
        ELSIF p_emp_position = 'staff' THEN
            INSERT INTO employee_staff (id, department)
            VALUES (p_id, p_department);
        END IF;
    ELSE
        -- Same position: update existing sub-type record
        IF COALESCE(p_emp_position, v_current_position) = 'driver' THEN
            UPDATE employee_driver
            SET license_number           = COALESCE(p_license_number,     license_number),
                license_category         = COALESCE(p_license_category,   license_category),
                license_expiry_date      = COALESCE(p_license_expiry,     license_expiry_date),
                driving_experience_years = COALESCE(p_driving_experience, driving_experience_years),
                driver_status            = COALESCE(p_driver_status,      driver_status)
            WHERE id = p_id;
        ELSIF COALESCE(p_emp_position, v_current_position) = 'staff' THEN
            UPDATE employee_staff
            SET department = COALESCE(p_department, department)
            WHERE id = p_id;
        END IF;
    END IF;
END;
$$;


-- 14. sp_delete_employee  [Employee]
-- Delete employee and sub-type records. Soft-deletes the user.
-- Prevents deletion if driver has active routes or deliveries.
CREATE OR REPLACE PROCEDURE sp_delete_employee(p_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_position VARCHAR(32);
BEGIN
    -- Get position to know which sub-type to delete
    SELECT emp_position INTO v_position FROM employee WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Employee with id % not found', p_id;
    END IF;

    -- Check for active routes (if driver)
    IF v_position = 'driver' THEN
        IF EXISTS (
            SELECT 1 FROM route
            WHERE driver_id = p_id
              AND delivery_status IN ('not_started', 'on_going')
        ) THEN
            RAISE EXCEPTION 'Cannot delete driver %: assigned to active routes', p_id;
        END IF;

        IF EXISTS (
            SELECT 1 FROM delivery
            WHERE driver_id = p_id
              AND status NOT IN ('completed', 'cancelled')
        ) THEN
            RAISE EXCEPTION 'Cannot delete driver %: has active deliveries', p_id;
        END IF;
    END IF;

    -- Delete sub-type record first (FK constraint: child before parent)
    IF v_position = 'driver' THEN
        DELETE FROM employee_driver WHERE id = p_id;
    ELSIF v_position = 'staff' THEN
        DELETE FROM employee_staff WHERE id = p_id;
    END IF;

    -- Delete employee record
    DELETE FROM employee WHERE id = p_id;

    -- Soft-delete the user (don't hard-delete, keep for audit trail)
    UPDATE "USER"
    SET is_active  = false,
        updated_at = NOW()
    WHERE id = p_id;
END;
$$;


/* ---------- WAREHOUSE ---------- */

-- 15. sp_create_warehouse  [Warehouse]
-- Create a new warehouse.
-- trg_warehouse_schedule_check validates open/close times automatically.
CREATE OR REPLACE PROCEDURE sp_create_warehouse(
    p_name                      VARCHAR(100),
    p_contact                   VARCHAR(20),
    p_address                   VARCHAR(255),
    p_maximum_storage_capacity  INT,
    p_schedule_open             TIME    DEFAULT NULL,
    p_schedule_close            TIME    DEFAULT NULL,
    p_schedule                  TEXT    DEFAULT NULL,
    INOUT p_id                  INT     DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO warehouse (
        name, contact, address,
        schedule_open, schedule_close, schedule,
        maximum_storage_capacity,
        is_active, created_at, updated_at
    ) VALUES (
        p_name, p_contact, p_address,
        p_schedule_open, p_schedule_close, p_schedule,
        p_maximum_storage_capacity,
        true, NOW(), NOW()
    )
    RETURNING id INTO p_id;
END;
$$;


-- 16. sp_update_warehouse  [Warehouse]
-- Update an existing warehouse's mutable fields.
CREATE OR REPLACE PROCEDURE sp_update_warehouse(
    p_id                        INT,
    p_name                      VARCHAR(100)  DEFAULT NULL,
    p_contact                   VARCHAR(20)   DEFAULT NULL,
    p_address                   VARCHAR(255)  DEFAULT NULL,
    p_schedule_open             TIME          DEFAULT NULL,
    p_schedule_close            TIME          DEFAULT NULL,
    p_schedule                  TEXT          DEFAULT NULL,
    p_maximum_storage_capacity  INT           DEFAULT NULL,
    p_is_active                 BOOL          DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE warehouse
    SET name                     = COALESCE(p_name,                      name),
        contact                  = COALESCE(p_contact,                   contact),
        address                  = COALESCE(p_address,                   address),
        schedule_open            = COALESCE(p_schedule_open,             schedule_open),
        schedule_close           = COALESCE(p_schedule_close,            schedule_close),
        schedule                 = COALESCE(p_schedule,                  schedule),
        maximum_storage_capacity = COALESCE(p_maximum_storage_capacity,  maximum_storage_capacity),
        is_active                = COALESCE(p_is_active,                 is_active),
        updated_at               = NOW()
    WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Warehouse with id % not found', p_id;
    END IF;
END;
$$;


-- 17. sp_delete_warehouse  [Warehouse]
-- Delete a warehouse. Prevents deletion if it has active employees or routes.
CREATE OR REPLACE PROCEDURE sp_delete_warehouse(p_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Check for active employees assigned to this warehouse
    IF EXISTS (
        SELECT 1 FROM employee
        WHERE war_id = p_id AND is_active = true
    ) THEN
        RAISE EXCEPTION 'Cannot delete warehouse %: it has active employees assigned.', p_id;
    END IF;

    -- Check for active routes dispatched from this warehouse
    IF EXISTS (
        SELECT 1 FROM route
        WHERE war_id = p_id
          AND delivery_status IN ('not_started', 'on_going')
    ) THEN
        RAISE EXCEPTION 'Cannot delete warehouse %: it has active routes.', p_id;
    END IF;

    DELETE FROM warehouse WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Warehouse with id % not found', p_id;
    END IF;
END;
$$;


-- 18. sp_import_warehouses  [Warehouse]
-- Bulk-import warehouses from a JSONB array.
CREATE OR REPLACE PROCEDURE sp_import_warehouses(p_data JSONB)
LANGUAGE plpgsql
AS $$
DECLARE
    v_rec JSONB;
BEGIN
    FOR v_rec IN SELECT jsonb_array_elements(p_data)
    LOOP
        INSERT INTO warehouse (
            name, contact, address,
            schedule_open, schedule_close, schedule,
            maximum_storage_capacity,
            is_active, created_at, updated_at
        ) VALUES (
            v_rec->>'name',
            v_rec->>'contact',
            v_rec->>'address',
            (v_rec->>'schedule_open')::TIME,
            (v_rec->>'schedule_close')::TIME,
            v_rec->>'schedule',
            (v_rec->>'maximum_storage_capacity')::INT,
            COALESCE((v_rec->>'is_active')::BOOL, true),
            NOW(), NOW()
        );
    END LOOP;
END;
$$;


/*==============================================================*/
/* END OF diego_objects.sql                                      */
/* Total: 18 standalone SQL blocks (20 objects counting         */
/*        driver/staff logic inside sp_create_employee)         */
/*==============================================================*/
