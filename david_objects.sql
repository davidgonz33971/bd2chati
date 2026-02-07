/*==============================================================*/
/* david_objects.sql                                            */
/* Database Objects: Delivery (13) + DeliveryTracking (3)       */
/*                                                = 16 objects  */
/*                                                              */
/* Run order: Execute top-to-bottom in pgAdmin Query Tool.      */
/* All table/column names are unquoted lowercase except "USER". */
/*==============================================================*/


/*==============================================================*/
/* Table of Contents                                            */
/*--------------------------------------------------------------*/
/*  #  | Entity           | Type      | Name                   */
/*-----|------------------|-----------|------------------------ */
/*  1  | Delivery         | Function  | fn_is_valid_status_transition */
/*  2  | Delivery         | Function  | fn_get_client_deliveries */
/*  3  | Delivery         | Function  | fn_get_driver_deliveries */
/*  4  | DeliveryTracking | Function  | fn_get_delivery_tracking */
/*  5  | Delivery         | View      | v_deliveries_full      */
/*  6  | Delivery         | View      | v_deliveries_export    */
/*  7  | DeliveryTracking | View      | v_delivery_tracking    */
/*  8  | Delivery         | Trigger   | trg_delivery_soft_delete */
/*  9  | Delivery         | Trigger   | trg_delivery_status_workflow */
/* 10  | Delivery         | Trigger   | trg_delivery_timestamp_check */
/* 11  | DeliveryTracking | Trigger   | trg_delivery_tracking_log */
/* 12  | Delivery         | Procedure | sp_create_delivery     */
/* 13  | Delivery         | Procedure | sp_update_delivery     */
/* 14  | Delivery         | Procedure | sp_update_delivery_status */
/* 15  | Delivery         | Procedure | sp_delete_delivery     */
/* 16  | Delivery         | Procedure | sp_import_deliveries   */
/*==============================================================*/



/* ============================================================ */
/*                       F U N C T I O N S                      */
/* ============================================================ */


-- 1. fn_is_valid_status_transition  [Delivery]
-- Validate delivery status transitions.
-- Allowed transitions:
--   registered -> ready, cancelled
--   ready      -> pending, cancelled
--   pending    -> in_transit, cancelled
--   in_transit -> completed, cancelled
--   completed  -> (terminal, no transitions)
--   cancelled  -> (terminal, no transitions)
CREATE OR REPLACE FUNCTION fn_is_valid_status_transition(
    p_old_status VARCHAR(20),
    p_new_status VARCHAR(20)
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    -- Same status is always allowed (no-op update)
    IF p_old_status = p_new_status THEN
        RETURN TRUE;
    END IF;

    RETURN CASE p_old_status
        WHEN 'registered' THEN p_new_status IN ('ready', 'cancelled')
        WHEN 'ready'      THEN p_new_status IN ('pending', 'cancelled')
        WHEN 'pending'    THEN p_new_status IN ('in_transit', 'cancelled')
        WHEN 'in_transit' THEN p_new_status IN ('completed', 'cancelled')
        ELSE FALSE  -- completed and cancelled are terminal
    END;
END;
$$;


-- 2. fn_get_client_deliveries  [Delivery]
-- Return all deliveries for a specific client, with driver/route info.
CREATE OR REPLACE FUNCTION fn_get_client_deliveries(p_client_id INT)
RETURNS TABLE (
    id                INT,
    tracking_number   VARCHAR(50),
    description       TEXT,
    sender_name       VARCHAR(100),
    recipient_name    VARCHAR(100),
    recipient_address TEXT,
    item_type         VARCHAR(20),
    weight            INT,
    dimensions        VARCHAR(50),
    status            VARCHAR(20),
    priority          VARCHAR(20),
    in_transition     BOOL,
    delivery_date     TIMESTAMPTZ,
    driver_name       TEXT,
    route_id          INT,
    warehouse_name    VARCHAR(100),
    created_at        TIMESTAMPTZ,
    updated_at        TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.id,
        d.tracking_number,
        d.description,
        d.sender_name,
        d.recipient_name,
        d.recipient_address,
        d.item_type,
        d.weight,
        d.dimensions,
        d.status,
        d.priority,
        d.in_transition,
        d.delivery_date,
        u_driver.first_name || ' ' || u_driver.last_name  AS driver_name,
        d.route_id,
        w.name                                              AS warehouse_name,
        d.created_at,
        d.updated_at
    FROM delivery d
    LEFT JOIN employee_driver ed   ON ed.id = d.driver_id
    LEFT JOIN "USER" u_driver      ON u_driver.id = ed.id
    LEFT JOIN warehouse w          ON w.id = d.war_id
    WHERE d.client_id = p_client_id
    ORDER BY d.created_at DESC;
END;
$$;


-- 3. fn_get_driver_deliveries  [Delivery]
-- Return all deliveries for a specific driver, with client/route info.
CREATE OR REPLACE FUNCTION fn_get_driver_deliveries(p_driver_id INT)
RETURNS TABLE (
    id                INT,
    tracking_number   VARCHAR(50),
    description       TEXT,
    sender_name       VARCHAR(100),
    recipient_name    VARCHAR(100),
    recipient_address TEXT,
    item_type         VARCHAR(20),
    weight            INT,
    dimensions        VARCHAR(50),
    status            VARCHAR(20),
    priority          VARCHAR(20),
    in_transition     BOOL,
    delivery_date     TIMESTAMPTZ,
    client_name       TEXT,
    route_id          INT,
    warehouse_name    VARCHAR(100),
    created_at        TIMESTAMPTZ,
    updated_at        TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.id,
        d.tracking_number,
        d.description,
        d.sender_name,
        d.recipient_name,
        d.recipient_address,
        d.item_type,
        d.weight,
        d.dimensions,
        d.status,
        d.priority,
        d.in_transition,
        d.delivery_date,
        u_client.first_name || ' ' || u_client.last_name  AS client_name,
        d.route_id,
        w.name                                              AS warehouse_name,
        d.created_at,
        d.updated_at
    FROM delivery d
    LEFT JOIN client c             ON c.id = d.client_id
    LEFT JOIN "USER" u_client      ON u_client.id = c.id
    LEFT JOIN warehouse w          ON w.id = d.war_id
    WHERE d.driver_id = p_driver_id
    ORDER BY d.created_at DESC;
END;
$$;


-- 4. fn_get_delivery_tracking  [DeliveryTracking]
-- Return the full tracking timeline for a delivery by tracking number.
-- Joins delivery_tracking with delivery, employee_staff, warehouse.
CREATE OR REPLACE FUNCTION fn_get_delivery_tracking(p_tracking_number VARCHAR(50))
RETURNS TABLE (
    tracking_id       INT,
    delivery_id       INT,
    tracking_number   VARCHAR(50),
    status            VARCHAR(20),
    notes             TEXT,
    changed_by_name   TEXT,
    warehouse_name    VARCHAR(100),
    event_timestamp   TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        dt.id              AS tracking_id,
        dt.del_id          AS delivery_id,
        d.tracking_number,
        dt.status,
        dt.notes,
        u_staff.first_name || ' ' || u_staff.last_name  AS changed_by_name,
        w.name                                            AS warehouse_name,
        dt.created_at      AS event_timestamp
    FROM delivery_tracking dt
    JOIN delivery d             ON d.id  = dt.del_id
    LEFT JOIN employee_staff es ON es.id = dt.staff_id
    LEFT JOIN "USER" u_staff    ON u_staff.id = es.id
    LEFT JOIN warehouse w       ON w.id  = dt.war_id
    WHERE d.tracking_number = p_tracking_number
    ORDER BY dt.created_at ASC;
END;
$$;



/* ============================================================ */
/*                          V I E W S                           */
/* ============================================================ */


-- 5. v_deliveries_full  [Delivery]
-- Deliveries joined with driver, client, route, and warehouse info.
CREATE OR REPLACE VIEW v_deliveries_full AS
SELECT
    d.id,
    d.tracking_number,
    d.description,
    d.sender_name,
    d.sender_address,
    d.sender_phone,
    d.sender_email,
    d.recipient_name,
    d.recipient_address,
    d.recipient_phone,
    d.recipient_email,
    d.item_type,
    d.weight,
    d.dimensions,
    d.status,
    d.priority,
    d.in_transition,
    d.delivery_date,
    d.created_at,
    d.updated_at,
    -- FKs
    d.driver_id,
    d.route_id,
    d.inv_id,
    d.client_id,
    d.war_id,
    -- Driver info
    u_driver.first_name || ' ' || u_driver.last_name  AS driver_name,
    -- Client info
    u_client.first_name || ' ' || u_client.last_name  AS client_name,
    -- Route info
    r.delivery_status                                   AS route_status,
    r.delivery_date                                     AS route_date,
    -- Warehouse info
    w.name                                              AS warehouse_name
FROM delivery d
LEFT JOIN employee_driver ed   ON ed.id = d.driver_id
LEFT JOIN "USER" u_driver      ON u_driver.id = ed.id
LEFT JOIN client c             ON c.id = d.client_id
LEFT JOIN "USER" u_client      ON u_client.id = c.id
LEFT JOIN route r              ON r.id = d.route_id
LEFT JOIN warehouse w          ON w.id = d.war_id
ORDER BY d.created_at DESC;


-- 6. v_deliveries_export  [Delivery]
-- Flat view formatted for JSON/CSV export.
CREATE OR REPLACE VIEW v_deliveries_export AS
SELECT
    d.id,
    d.driver_id,
    d.route_id,
    d.inv_id,
    d.client_id,
    d.war_id,
    d.tracking_number,
    d.description,
    d.sender_name,
    d.sender_address,
    d.sender_phone,
    d.sender_email,
    d.recipient_name,
    d.recipient_address,
    d.recipient_phone,
    d.recipient_email,
    d.item_type,
    d.weight,
    d.dimensions,
    d.status,
    d.priority,
    d.in_transition,
    d.delivery_date,
    d.created_at,
    d.updated_at
FROM delivery d
ORDER BY d.id;


-- 7. v_delivery_tracking  [DeliveryTracking]
-- Full tracking timeline view joining delivery_tracking with delivery, employee_staff, warehouse.
CREATE OR REPLACE VIEW v_delivery_tracking AS
SELECT
    dt.id              AS tracking_id,
    dt.del_id          AS delivery_id,
    d.tracking_number,
    dt.status,
    dt.notes,
    dt.staff_id,
    u_staff.first_name || ' ' || u_staff.last_name  AS staff_name,
    dt.war_id,
    w.name                                            AS warehouse_name,
    dt.created_at      AS event_timestamp
FROM delivery_tracking dt
JOIN delivery d             ON d.id  = dt.del_id
LEFT JOIN employee_staff es ON es.id = dt.staff_id
LEFT JOIN "USER" u_staff    ON u_staff.id = es.id
LEFT JOIN warehouse w       ON w.id  = dt.war_id
ORDER BY dt.del_id, dt.created_at ASC;



/* ============================================================ */
/*                       T R I G G E R S                        */
/* ============================================================ */


-- 8. trg_delivery_soft_delete  [Delivery]
-- BEFORE DELETE on delivery: set status='cancelled' instead of hard-deleting.
CREATE OR REPLACE FUNCTION fn_trg_delivery_soft_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE delivery
    SET status     = 'cancelled',
        updated_at = NOW()
    WHERE id = OLD.id;

    -- Cancel the DELETE so the row stays in the table
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_delivery_soft_delete ON delivery;

CREATE TRIGGER trg_delivery_soft_delete
    BEFORE DELETE ON delivery
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_delivery_soft_delete();


-- 9. trg_delivery_status_workflow  [Delivery]
-- BEFORE UPDATE on delivery: enforce valid status transitions.
-- Depends on: fn_is_valid_status_transition
CREATE OR REPLACE FUNCTION fn_trg_delivery_status_workflow()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Only check when status is actually changing
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        IF NOT fn_is_valid_status_transition(OLD.status, NEW.status) THEN
            RAISE EXCEPTION 'Invalid status transition: % -> %. Allowed from %: %',
                OLD.status, NEW.status, OLD.status,
                CASE OLD.status
                    WHEN 'registered' THEN 'ready, cancelled'
                    WHEN 'ready'      THEN 'pending, cancelled'
                    WHEN 'pending'    THEN 'in_transit, cancelled'
                    WHEN 'in_transit' THEN 'completed, cancelled'
                    ELSE '(none — terminal status)'
                END;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_delivery_status_workflow ON delivery;

CREATE TRIGGER trg_delivery_status_workflow
    BEFORE UPDATE ON delivery
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_delivery_status_workflow();


-- 10. trg_delivery_timestamp_check  [Delivery]
-- BEFORE INSERT/UPDATE on delivery: ensure updated_at >= created_at.
-- Also auto-sets updated_at = NOW() on UPDATE.
CREATE OR REPLACE FUNCTION fn_trg_delivery_timestamp_check()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- On INSERT: set timestamps if not provided
    IF TG_OP = 'INSERT' THEN
        NEW.created_at := COALESCE(NEW.created_at, NOW());
        NEW.updated_at := COALESCE(NEW.updated_at, NOW());
    END IF;

    -- On UPDATE: always bump updated_at
    IF TG_OP = 'UPDATE' THEN
        NEW.updated_at := NOW();
    END IF;

    -- Validate updated_at >= created_at
    IF NEW.updated_at < NEW.created_at THEN
        RAISE EXCEPTION 'updated_at (%) cannot be before created_at (%)',
            NEW.updated_at, NEW.created_at;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_delivery_timestamp_check ON delivery;

CREATE TRIGGER trg_delivery_timestamp_check
    BEFORE INSERT OR UPDATE ON delivery
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_delivery_timestamp_check();


-- 11. trg_delivery_tracking_log  [DeliveryTracking]
-- AFTER INSERT OR UPDATE OF status ON delivery:
-- Automatically insert a row into delivery_tracking to record the status change.
-- The staff_id and war_id are taken from the delivery row itself
-- (set by sp_update_delivery_status before the trigger fires).
CREATE OR REPLACE FUNCTION fn_trg_delivery_tracking_log()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- On INSERT: log the initial status
    -- On UPDATE of status: log the new status
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status) THEN
        INSERT INTO delivery_tracking (
            del_id, staff_id, war_id,
            status, notes, created_at
        ) VALUES (
            NEW.id,
            NULL,       -- staff_id set to NULL on auto-log; sp_update_delivery_status handles it
            NEW.war_id,
            NEW.status,
            CASE
                WHEN TG_OP = 'INSERT' THEN 'Delivery registered'
                ELSE 'Status changed to ' || NEW.status
            END,
            NOW()
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_delivery_tracking_log ON delivery;

CREATE TRIGGER trg_delivery_tracking_log
    AFTER INSERT OR UPDATE OF status ON delivery
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_delivery_tracking_log();



/* ============================================================ */
/*                     P R O C E D U R E S                      */
/* ============================================================ */


/* ---------- DELIVERY ---------- */

-- 12. sp_create_delivery  [Delivery]
-- Create a new delivery with validation.
-- Auto-generates tracking_number if not provided.
-- Triggers trg_delivery_timestamp_check (timestamps) and trg_delivery_tracking_log (initial event).
CREATE OR REPLACE PROCEDURE sp_create_delivery(
    p_driver_id          INT         DEFAULT NULL,
    p_route_id           INT         DEFAULT NULL,
    p_inv_id             INT         DEFAULT NULL,
    p_client_id          INT         DEFAULT NULL,
    p_war_id             INT         DEFAULT NULL,
    p_tracking_number    VARCHAR(50) DEFAULT NULL,
    p_description        TEXT        DEFAULT NULL,
    p_sender_name        VARCHAR(100) DEFAULT NULL,
    p_sender_address     TEXT        DEFAULT NULL,
    p_sender_phone       VARCHAR(20) DEFAULT NULL,
    p_sender_email       VARCHAR(100) DEFAULT NULL,
    p_recipient_name     VARCHAR(100) DEFAULT NULL,
    p_recipient_address  TEXT        DEFAULT NULL,
    p_recipient_phone    VARCHAR(20) DEFAULT NULL,
    p_recipient_email    VARCHAR(100) DEFAULT NULL,
    p_item_type          VARCHAR(20) DEFAULT NULL,
    p_weight             INT         DEFAULT NULL,
    p_dimensions         VARCHAR(50) DEFAULT NULL,
    p_status             VARCHAR(20) DEFAULT 'registered',
    p_priority           VARCHAR(20) DEFAULT 'normal',
    p_delivery_date      TIMESTAMPTZ DEFAULT NULL,
    INOUT p_id           INT         DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_tracking VARCHAR(50);
BEGIN
    -- Validate weight if provided
    IF p_weight IS NOT NULL AND p_weight < 1 THEN
        RAISE EXCEPTION 'Weight must be >= 1, got %', p_weight;
    END IF;

    -- Validate FK: client exists (if provided)
    IF p_client_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM client WHERE id = p_client_id) THEN
        RAISE EXCEPTION 'Client with id % not found', p_client_id;
    END IF;

    -- Validate FK: driver exists (if provided)
    IF p_driver_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM employee_driver WHERE id = p_driver_id) THEN
        RAISE EXCEPTION 'Driver with id % not found', p_driver_id;
    END IF;

    -- Validate FK: route exists (if provided)
    IF p_route_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM route WHERE id = p_route_id) THEN
        RAISE EXCEPTION 'Route with id % not found', p_route_id;
    END IF;

    -- Auto-generate tracking number if not provided: PO-YYYYMMDD-XXXXX
    IF p_tracking_number IS NULL OR p_tracking_number = '' THEN
        v_tracking := 'PO-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' ||
                      LPAD(nextval(pg_get_serial_sequence('delivery', 'id'))::TEXT, 5, '0');
    ELSE
        v_tracking := p_tracking_number;
    END IF;

    INSERT INTO delivery (
        driver_id, route_id, inv_id, client_id, war_id,
        tracking_number, description,
        sender_name, sender_address, sender_phone, sender_email,
        recipient_name, recipient_address, recipient_phone, recipient_email,
        item_type, weight, dimensions,
        status, priority, in_transition,
        delivery_date, created_at, updated_at
    ) VALUES (
        p_driver_id, p_route_id, p_inv_id, p_client_id, p_war_id,
        v_tracking, p_description,
        p_sender_name, p_sender_address, p_sender_phone, p_sender_email,
        p_recipient_name, p_recipient_address, p_recipient_phone, p_recipient_email,
        p_item_type, p_weight, p_dimensions,
        COALESCE(p_status, 'registered'), COALESCE(p_priority, 'normal'), false,
        p_delivery_date, NOW(), NOW()
    )
    RETURNING id INTO p_id;

    -- trg_delivery_timestamp_check validates timestamps
    -- trg_delivery_tracking_log inserts the initial tracking event
END;
$$;


-- 13. sp_update_delivery  [Delivery]
-- Update a delivery's mutable fields (NOT status — use sp_update_delivery_status for that).
CREATE OR REPLACE PROCEDURE sp_update_delivery(
    p_id                 INT,
    p_driver_id          INT          DEFAULT NULL,
    p_route_id           INT          DEFAULT NULL,
    p_inv_id             INT          DEFAULT NULL,
    p_client_id          INT          DEFAULT NULL,
    p_war_id             INT          DEFAULT NULL,
    p_tracking_number    VARCHAR(50)  DEFAULT NULL,
    p_description        TEXT         DEFAULT NULL,
    p_sender_name        VARCHAR(100) DEFAULT NULL,
    p_sender_address     TEXT         DEFAULT NULL,
    p_sender_phone       VARCHAR(20)  DEFAULT NULL,
    p_sender_email       VARCHAR(100) DEFAULT NULL,
    p_recipient_name     VARCHAR(100) DEFAULT NULL,
    p_recipient_address  TEXT         DEFAULT NULL,
    p_recipient_phone    VARCHAR(20)  DEFAULT NULL,
    p_recipient_email    VARCHAR(100) DEFAULT NULL,
    p_item_type          VARCHAR(20)  DEFAULT NULL,
    p_weight             INT          DEFAULT NULL,
    p_dimensions         VARCHAR(50)  DEFAULT NULL,
    p_priority           VARCHAR(20)  DEFAULT NULL,
    p_in_transition      BOOL         DEFAULT NULL,
    p_delivery_date      TIMESTAMPTZ  DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Validate weight if provided
    IF p_weight IS NOT NULL AND p_weight < 1 THEN
        RAISE EXCEPTION 'Weight must be >= 1, got %', p_weight;
    END IF;

    UPDATE delivery
    SET driver_id         = COALESCE(p_driver_id,         driver_id),
        route_id          = COALESCE(p_route_id,          route_id),
        inv_id            = COALESCE(p_inv_id,            inv_id),
        client_id         = COALESCE(p_client_id,         client_id),
        war_id            = COALESCE(p_war_id,            war_id),
        tracking_number   = COALESCE(p_tracking_number,   tracking_number),
        description       = COALESCE(p_description,       description),
        sender_name       = COALESCE(p_sender_name,       sender_name),
        sender_address    = COALESCE(p_sender_address,    sender_address),
        sender_phone      = COALESCE(p_sender_phone,      sender_phone),
        sender_email      = COALESCE(p_sender_email,      sender_email),
        recipient_name    = COALESCE(p_recipient_name,    recipient_name),
        recipient_address = COALESCE(p_recipient_address, recipient_address),
        recipient_phone   = COALESCE(p_recipient_phone,   recipient_phone),
        recipient_email   = COALESCE(p_recipient_email,   recipient_email),
        item_type         = COALESCE(p_item_type,         item_type),
        weight            = COALESCE(p_weight,            weight),
        dimensions        = COALESCE(p_dimensions,        dimensions),
        priority          = COALESCE(p_priority,          priority),
        in_transition     = COALESCE(p_in_transition,     in_transition),
        delivery_date     = COALESCE(p_delivery_date,     delivery_date),
        updated_at        = NOW()
    WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Delivery with id % not found', p_id;
    END IF;

    -- trg_delivery_timestamp_check validates timestamps
END;
$$;


-- 14. sp_update_delivery_status  [Delivery]
-- Update ONLY the delivery status, with staff/warehouse context for tracking.
-- This fires trg_delivery_status_workflow (validates transition)
-- and trg_delivery_tracking_log (inserts tracking event).
-- After the auto-logged event, we update it with the staff_id and notes.
CREATE OR REPLACE PROCEDURE sp_update_delivery_status(
    p_delivery_id    INT,
    p_new_status     VARCHAR(20),
    p_staff_id       INT          DEFAULT NULL,
    p_warehouse_id   INT          DEFAULT NULL,
    p_notes          TEXT         DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_tracking_id INT;
BEGIN
    -- Validate delivery exists
    IF NOT EXISTS (SELECT 1 FROM delivery WHERE id = p_delivery_id) THEN
        RAISE EXCEPTION 'Delivery with id % not found', p_delivery_id;
    END IF;

    -- Update the delivery status
    -- trg_delivery_status_workflow validates the transition
    -- trg_delivery_tracking_log auto-inserts a tracking row
    UPDATE delivery
    SET status     = p_new_status,
        updated_at = NOW()
    WHERE id = p_delivery_id;

    -- Now update the most recent tracking event with staff/warehouse/notes context
    SELECT id INTO v_tracking_id
    FROM delivery_tracking
    WHERE del_id = p_delivery_id
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_tracking_id IS NOT NULL THEN
        UPDATE delivery_tracking
        SET staff_id = COALESCE(p_staff_id, staff_id),
            war_id   = COALESCE(p_warehouse_id, war_id),
            notes    = COALESCE(p_notes, notes)
        WHERE id = v_tracking_id;
    END IF;
END;
$$;


-- 15. sp_delete_delivery  [Delivery]
-- Soft-delete a delivery (triggers trg_delivery_soft_delete -> sets status='cancelled').
CREATE OR REPLACE PROCEDURE sp_delete_delivery(p_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    -- The BEFORE DELETE trigger converts this into a soft delete
    DELETE FROM delivery WHERE id = p_id;

    -- After the trigger fires, the row still exists — verify the status was set
    IF NOT EXISTS (SELECT 1 FROM delivery WHERE id = p_id AND status = 'cancelled') THEN
        RAISE EXCEPTION 'Delivery with id % not found', p_id;
    END IF;
END;
$$;


-- 16. sp_import_deliveries  [Delivery]
-- Bulk-import deliveries from a JSONB array.
-- Auto-generates tracking_number for each if not provided.
-- Triggers fire per row (timestamp check + tracking log).
CREATE OR REPLACE PROCEDURE sp_import_deliveries(p_data JSONB)
LANGUAGE plpgsql
AS $$
DECLARE
    v_rec       JSONB;
    v_tracking  VARCHAR(50);
    v_del_id    INT;
BEGIN
    FOR v_rec IN SELECT jsonb_array_elements(p_data)
    LOOP
        -- Auto-generate tracking number if not provided
        IF (v_rec->>'tracking_number') IS NULL OR (v_rec->>'tracking_number') = '' THEN
            v_tracking := 'PO-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' ||
                          LPAD(nextval(pg_get_serial_sequence('delivery', 'id'))::TEXT, 5, '0');
        ELSE
            v_tracking := v_rec->>'tracking_number';
        END IF;

        INSERT INTO delivery (
            driver_id, route_id, inv_id, client_id, war_id,
            tracking_number, description,
            sender_name, sender_address, sender_phone, sender_email,
            recipient_name, recipient_address, recipient_phone, recipient_email,
            item_type, weight, dimensions,
            status, priority, in_transition,
            delivery_date, created_at, updated_at
        ) VALUES (
            (v_rec->>'driver_id')::INT,
            (v_rec->>'route_id')::INT,
            (v_rec->>'inv_id')::INT,
            (v_rec->>'client_id')::INT,
            (v_rec->>'war_id')::INT,
            v_tracking,
            v_rec->>'description',
            v_rec->>'sender_name',
            v_rec->>'sender_address',
            v_rec->>'sender_phone',
            v_rec->>'sender_email',
            v_rec->>'recipient_name',
            v_rec->>'recipient_address',
            v_rec->>'recipient_phone',
            v_rec->>'recipient_email',
            v_rec->>'item_type',
            (v_rec->>'weight')::INT,
            v_rec->>'dimensions',
            COALESCE(v_rec->>'status', 'registered'),
            COALESCE(v_rec->>'priority', 'normal'),
            COALESCE((v_rec->>'in_transition')::BOOL, false),
            (v_rec->>'delivery_date')::TIMESTAMPTZ,
            NOW(), NOW()
        )
        RETURNING id INTO v_del_id;

        -- trg_delivery_timestamp_check and trg_delivery_tracking_log fire per row
    END LOOP;
END;
$$;


/*==============================================================*/
/* END OF david_objects.sql                                      */
/* Total: 16 objects                                            */
/*   Delivery: 2 views + 3 triggers + 3 functions + 5 procs    */
/*   DeliveryTracking: 1 view + 1 trigger + 1 function         */
/*==============================================================*/
