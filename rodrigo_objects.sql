/*==============================================================*/
/* rodrigo_objects.sql                                          */
/* Database Objects: Invoice (11) + InvoiceItem (4) +           */
/*                   Dashboard (3) + Vehicle (7) + Route (7)    */
/*                                                = 32 objects  */
/*                                                              */
/* Run order: Execute top-to-bottom in pgAdmin Query Tool.      */
/* All table/column names are unquoted lowercase except "USER". */
/*==============================================================*/


/*==============================================================*/
/* Table of Contents                                            */
/*--------------------------------------------------------------*/
/*  #  | Entity      | Type              | Name                 */
/*-----|-------------|-------------------|---------------------- */
/*  1  | Invoice     | Function          | fn_calculate_tax     */
/*  2  | InvoiceItem | Function          | fn_calculate_item_total */
/*  3  | Invoice     | Function          | fn_invoice_subtotal  */
/*  4  | Invoice     | Function          | fn_invoice_total     */
/*  5  | Vehicle     | Function          | fn_is_valid_year     */
/*  6  | Invoice     | View              | v_invoices_with_items*/
/*  7  | Invoice     | View              | v_invoices_export    */
/*  8  | Vehicle     | View              | v_vehicles_full      */
/*  9  | Vehicle     | View              | v_vehicles_export    */
/* 10  | Route       | View              | v_routes_full        */
/* 11  | Route       | View              | v_routes_export      */
/* 12  | Invoice     | Materialized View | mv_invoice_totals    */
/* 13  | Dashboard   | Materialized View | mv_dashboard_stats   */
/* 14  | Dashboard   | Function          | fn_get_dashboard_stats*/
/* 15  | InvoiceItem | Trigger           | trg_invoice_item_calc_total */
/* 16  | InvoiceItem | Trigger           | trg_invoice_update_cost */
/* 17  | Invoice     | Trigger           | trg_invoice_soft_delete */
/* 18  | Route       | Trigger           | trg_route_time_check */
/* 19  | Invoice     | Procedure         | sp_create_invoice    */
/* 20  | Invoice     | Procedure         | sp_update_invoice    */
/* 21  | Invoice     | Procedure         | sp_delete_invoice    */
/* 22  | Invoice     | Procedure         | sp_import_invoices   */
/* 23  | InvoiceItem | Procedure         | sp_add_invoice_item  */
/* 24  | Vehicle     | Procedure         | sp_create_vehicle    */
/* 25  | Vehicle     | Procedure         | sp_update_vehicle    */
/* 26  | Vehicle     | Procedure         | sp_delete_vehicle    */
/* 27  | Vehicle     | Procedure         | sp_import_vehicles   */
/* 28  | Route       | Procedure         | sp_create_route      */
/* 29  | Route       | Procedure         | sp_update_route      */
/* 30  | Route       | Procedure         | sp_delete_route      */
/* 31  | Route       | Procedure         | sp_import_routes     */
/*==============================================================*/



/* ============================================================ */
/*                       F U N C T I O N S                      */
/* ============================================================ */


-- 1. fn_calculate_tax
-- Calculate tax amount for a given value. Default rate 23%.
CREATE OR REPLACE FUNCTION fn_calculate_tax(
    p_amount DECIMAL(10,2),
    p_rate   DECIMAL(5,4) DEFAULT 0.23
)
RETURNS DECIMAL(10,2)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN ROUND(p_amount * p_rate, 2);
END;
$$;


-- 2. fn_calculate_item_total
-- Pure calculation: quantity * unit_price.
CREATE OR REPLACE FUNCTION fn_calculate_item_total(
    p_quantity   INT,
    p_unit_price DECIMAL(10,2)
)
RETURNS DECIMAL(10,2)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN COALESCE(p_quantity, 0) * COALESCE(p_unit_price, 0.00);
END;
$$;


-- 3. fn_invoice_subtotal
-- Sum of all total_item_cost for a given invoice.
CREATE OR REPLACE FUNCTION fn_invoice_subtotal(p_invoice_id INT)
RETURNS DECIMAL(10,2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_subtotal DECIMAL(10,2);
BEGIN
    SELECT COALESCE(SUM(total_item_cost), 0.00)
    INTO v_subtotal
    FROM invoice_item
    WHERE inv_id = p_invoice_id;

    RETURN v_subtotal;
END;
$$;


-- 4. fn_invoice_total
-- Subtotal + 23% tax for a given invoice.
-- Depends on: fn_invoice_subtotal, fn_calculate_tax
CREATE OR REPLACE FUNCTION fn_invoice_total(p_invoice_id INT)
RETURNS DECIMAL(10,2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_subtotal DECIMAL(10,2);
BEGIN
    v_subtotal := fn_invoice_subtotal(p_invoice_id);
    RETURN ROUND(v_subtotal + fn_calculate_tax(v_subtotal), 2);
END;
$$;


-- 5. fn_is_valid_year
-- Check that a vehicle year is between 1900 and current year + 1.
CREATE OR REPLACE FUNCTION fn_is_valid_year(p_year INT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN p_year IS NOT NULL
       AND p_year >= 1900
       AND p_year <= EXTRACT(YEAR FROM CURRENT_DATE)::INT + 1;
END;
$$;



/* ============================================================ */
/*                          V I E W S                           */
/* ============================================================ */


-- 6. v_invoices_with_items
-- Invoices joined with aggregated item counts and totals, plus warehouse/staff/client names.
CREATE OR REPLACE VIEW v_invoices_with_items AS
SELECT
    i.id,
    i.war_id,
    w.name                                              AS warehouse_name,
    i.staff_id,
    u_staff.first_name || ' ' || u_staff.last_name      AS staff_name,
    i.client_id,
    u_client.first_name || ' ' || u_client.last_name    AS client_name,
    i.status,
    i.type,
    i.quantity,
    i.cost,
    i.paid,
    i.pay_method,
    i.name,
    i.address,
    i.contact,
    i.created_at,
    i.updated_at,
    COALESCE(agg.item_count, 0)                          AS item_count,
    COALESCE(agg.subtotal, 0.00)                         AS subtotal,
    ROUND(COALESCE(agg.subtotal, 0.00) * 0.23, 2)       AS tax,
    ROUND(COALESCE(agg.subtotal, 0.00) * 1.23, 2)       AS total
FROM invoice i
LEFT JOIN warehouse w           ON w.id = i.war_id
LEFT JOIN employee_staff es     ON es.id = i.staff_id
LEFT JOIN "USER" u_staff        ON u_staff.id = es.id
LEFT JOIN client c              ON c.id = i.client_id
LEFT JOIN "USER" u_client       ON u_client.id = c.id
LEFT JOIN LATERAL (
    SELECT
        COUNT(*)                AS item_count,
        SUM(ii.total_item_cost) AS subtotal
    FROM invoice_item ii
    WHERE ii.inv_id = i.id
) agg ON true
ORDER BY i.created_at DESC;


-- 7. v_invoices_export
-- Flat view formatted for JSON/CSV export.
CREATE OR REPLACE VIEW v_invoices_export AS
SELECT
    i.id,
    i.war_id,
    i.staff_id,
    i.client_id,
    i.status,
    i.type,
    i.quantity,
    i.cost,
    i.paid,
    i.pay_method,
    i.name,
    i.address,
    i.contact,
    i.created_at,
    i.updated_at
FROM invoice i
ORDER BY i.id;


-- 8. v_vehicles_full
-- All vehicle data for list pages.
CREATE OR REPLACE VIEW v_vehicles_full AS
SELECT
    v.id,
    v.vehicle_type,
    v.plate_number,
    v.capacity,
    v.brand,
    v.model,
    v.vehicle_status,
    v.year,
    v.fuel_type,
    v.last_maintenance_date,
    v.is_active,
    v.created_at,
    v.updated_at
FROM vehicle v
ORDER BY v.id;


-- 9. v_vehicles_export
-- Flat view formatted for JSON/CSV export.
CREATE OR REPLACE VIEW v_vehicles_export AS
SELECT
    v.id,
    v.vehicle_type,
    v.plate_number,
    v.capacity,
    v.brand,
    v.model,
    v.vehicle_status,
    v.year,
    v.fuel_type,
    v.last_maintenance_date,
    v.is_active,
    v.created_at,
    v.updated_at
FROM vehicle v
ORDER BY v.id;


-- 10. v_routes_full
-- Routes joined with driver, vehicle, and warehouse info.
CREATE OR REPLACE VIEW v_routes_full AS
SELECT
    r.id,
    r.driver_id,
    u_driver.first_name || ' ' || u_driver.last_name AS driver_name,
    ed.license_number,
    ed.license_category,
    r.vehicle_id,
    v.plate_number,
    v.brand || ' ' || v.model                        AS vehicle_name,
    r.war_id,
    w.name                                            AS warehouse_name,
    r.description,
    r.delivery_status,
    r.delivery_date,
    r.delivery_start_time,
    r.delivery_end_time,
    r.expected_duration,
    r.kms_travelled,
    r.driver_notes,
    r.is_active,
    r.created_at,
    r.updated_at
FROM route r
LEFT JOIN employee_driver ed    ON ed.id = r.driver_id
LEFT JOIN "USER" u_driver       ON u_driver.id = ed.id
LEFT JOIN vehicle v             ON v.id = r.vehicle_id
LEFT JOIN warehouse w           ON w.id = r.war_id
ORDER BY r.delivery_date DESC NULLS LAST, r.id;


-- 11. v_routes_export
-- Flat view formatted for JSON/CSV export.
CREATE OR REPLACE VIEW v_routes_export AS
SELECT
    r.id,
    r.driver_id,
    r.vehicle_id,
    r.war_id,
    r.description,
    r.delivery_status,
    r.delivery_date,
    r.delivery_start_time,
    r.delivery_end_time,
    r.expected_duration,
    r.kms_travelled,
    r.driver_notes,
    r.is_active,
    r.created_at,
    r.updated_at
FROM route r
ORDER BY r.id;



/* ============================================================ */
/*               M A T E R I A L I Z E D   V I E W S           */
/* ============================================================ */


-- 12. mv_invoice_totals
-- Cached per-invoice subtotal, tax (23%), and grand total.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_invoice_totals AS
SELECT
    i.id                                                        AS invoice_id,
    COALESCE(SUM(ii.total_item_cost), 0.00)                     AS subtotal,
    ROUND(COALESCE(SUM(ii.total_item_cost), 0.00) * 0.23, 2)   AS tax,
    ROUND(COALESCE(SUM(ii.total_item_cost), 0.00) * 1.23, 2)   AS total,
    COUNT(ii.id)                                                AS item_count
FROM invoice i
LEFT JOIN invoice_item ii ON ii.inv_id = i.id
GROUP BY i.id
ORDER BY i.id;

-- Unique index required for REFRESH CONCURRENTLY
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_invoice_totals_pk
    ON mv_invoice_totals (invoice_id);


-- 13. mv_dashboard_stats
-- Cached aggregate counts for the admin dashboard.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_dashboard_stats AS
SELECT
    (SELECT COUNT(*) FROM vehicle WHERE is_active = true)                                   AS total_vehicles,
    (SELECT COUNT(*) FROM delivery)                                                         AS total_deliveries,
    (SELECT COUNT(*) FROM "USER" WHERE role = 'client')                                     AS total_clients,
    (SELECT COUNT(*) FROM employee WHERE is_active = true)                                  AS total_employees,
    (SELECT COUNT(*) FROM route WHERE delivery_status NOT IN ('finished', 'cancelled'))     AS active_routes,
    (SELECT COUNT(*) FROM delivery WHERE status = 'pending')                                AS pending_deliveries,
    (SELECT COUNT(*) FROM invoice)                                                          AS total_invoices;

-- Unique index (single-row view, use constant)
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_dashboard_stats_pk
    ON mv_dashboard_stats ((1));


-- 14. fn_get_dashboard_stats
-- Returns role-specific dashboard data as key-value pairs.
-- Depends on: mv_dashboard_stats
CREATE OR REPLACE FUNCTION fn_get_dashboard_stats(
    p_user_id INT,
    p_role    VARCHAR(20)
)
RETURNS TABLE (
    stat_name  TEXT,
    stat_value BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_role IN ('admin', 'manager') THEN
        RETURN QUERY
        SELECT 'total_vehicles'::TEXT,      ds.total_vehicles      FROM mv_dashboard_stats ds
        UNION ALL
        SELECT 'total_deliveries'::TEXT,    ds.total_deliveries    FROM mv_dashboard_stats ds
        UNION ALL
        SELECT 'total_clients'::TEXT,       ds.total_clients       FROM mv_dashboard_stats ds
        UNION ALL
        SELECT 'total_employees'::TEXT,     ds.total_employees     FROM mv_dashboard_stats ds
        UNION ALL
        SELECT 'active_routes'::TEXT,       ds.active_routes       FROM mv_dashboard_stats ds
        UNION ALL
        SELECT 'pending_deliveries'::TEXT,  ds.pending_deliveries  FROM mv_dashboard_stats ds
        UNION ALL
        SELECT 'total_invoices'::TEXT,      ds.total_invoices      FROM mv_dashboard_stats ds;

    ELSIF p_role = 'driver' THEN
        RETURN QUERY
        SELECT 'my_deliveries'::TEXT, COUNT(*)::BIGINT
        FROM delivery
        WHERE driver_id = p_user_id;

    ELSIF p_role = 'client' THEN
        RETURN QUERY
        SELECT 'my_deliveries'::TEXT, COUNT(*)::BIGINT
        FROM delivery
        WHERE client_id = p_user_id;

    ELSE  -- staff or other
        RETURN QUERY
        SELECT 'total_deliveries'::TEXT, COUNT(*)::BIGINT
        FROM delivery;
    END IF;
END;
$$;



/* ============================================================ */
/*                       T R I G G E R S                        */
/* ============================================================ */


-- 15. trg_invoice_item_calc_total
-- BEFORE INSERT/UPDATE on invoice_item: auto-calculate total_item_cost = quantity * unit_price.
CREATE OR REPLACE FUNCTION fn_trg_invoice_item_calc_total()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.total_item_cost := COALESCE(NEW.quantity, 0) * COALESCE(NEW.unit_price, 0.00);
    NEW.updated_at      := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_invoice_item_calc_total ON invoice_item;

CREATE TRIGGER trg_invoice_item_calc_total
    BEFORE INSERT OR UPDATE ON invoice_item
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_invoice_item_calc_total();


-- 16. trg_invoice_update_cost
-- AFTER INSERT/UPDATE/DELETE on invoice_item: recalculate the parent invoice cost and quantity.
CREATE OR REPLACE FUNCTION fn_trg_invoice_update_cost()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_inv_id INT;
BEGIN
    -- Determine which invoice was affected
    IF TG_OP = 'DELETE' THEN
        v_inv_id := OLD.inv_id;
    ELSE
        v_inv_id := NEW.inv_id;
    END IF;

    -- Recalculate invoice cost and quantity from its items
    UPDATE invoice
    SET cost       = COALESCE(sub.total_cost, 0.00),
        quantity   = COALESCE(sub.total_qty, 0),
        updated_at = NOW()
    FROM (
        SELECT
            SUM(total_item_cost) AS total_cost,
            SUM(quantity)        AS total_qty
        FROM invoice_item
        WHERE inv_id = v_inv_id
    ) sub
    WHERE invoice.id = v_inv_id;

    -- Refresh the materialized view
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_invoice_totals;

    RETURN NULL;  -- AFTER trigger, return value is ignored
END;
$$;

DROP TRIGGER IF EXISTS trg_invoice_update_cost ON invoice_item;

CREATE TRIGGER trg_invoice_update_cost
    AFTER INSERT OR UPDATE OR DELETE ON invoice_item
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_invoice_update_cost();


-- 17. trg_invoice_soft_delete
-- BEFORE DELETE on invoice: set status='cancelled' instead of hard-deleting.
CREATE OR REPLACE FUNCTION fn_trg_invoice_soft_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE invoice
    SET status     = 'cancelled',
        updated_at = NOW()
    WHERE id = OLD.id;

    -- Cancel the DELETE so the row stays in the table
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_invoice_soft_delete ON invoice;

CREATE TRIGGER trg_invoice_soft_delete
    BEFORE DELETE ON invoice
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_invoice_soft_delete();


-- 18. trg_route_time_check
-- BEFORE INSERT/UPDATE on route: ensure delivery_end_time > delivery_start_time (when both set).
CREATE OR REPLACE FUNCTION fn_trg_route_time_check()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.delivery_start_time IS NOT NULL
       AND NEW.delivery_end_time IS NOT NULL
       AND NEW.delivery_end_time <= NEW.delivery_start_time
    THEN
        RAISE EXCEPTION 'Route end time (%) must be after start time (%)',
            NEW.delivery_end_time, NEW.delivery_start_time;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_route_time_check ON route;

CREATE TRIGGER trg_route_time_check
    BEFORE INSERT OR UPDATE ON route
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_route_time_check();



/* ============================================================ */
/*                     P R O C E D U R E S                      */
/* ============================================================ */


/* ---------- INVOICE ---------- */

-- 19. sp_create_invoice
-- Create a new invoice header row.
CREATE OR REPLACE PROCEDURE sp_create_invoice(
    p_war_id        INT,
    p_staff_id      INT,
    p_client_id     INT,
    p_status        VARCHAR(30),
    p_type          VARCHAR(30),
    p_quantity      INT,
    p_cost          DECIMAL(10,2),
    p_paid          BOOL,
    p_pay_method    VARCHAR(30),
    p_name          TEXT,
    p_address       TEXT,
    p_contact       TEXT,
    INOUT p_id      INT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO invoice (
        war_id, staff_id, client_id,
        status, type, quantity, cost,
        paid, pay_method,
        name, address, contact,
        created_at, updated_at
    ) VALUES (
        p_war_id, p_staff_id, p_client_id,
        COALESCE(p_status, 'pending'), p_type, p_quantity, COALESCE(p_cost, 0.00),
        COALESCE(p_paid, false), p_pay_method,
        p_name, p_address, p_contact,
        NOW(), NOW()
    )
    RETURNING id INTO p_id;
END;
$$;


-- 20. sp_update_invoice
-- Update an existing invoice's mutable fields.
CREATE OR REPLACE PROCEDURE sp_update_invoice(
    p_id            INT,
    p_war_id        INT         DEFAULT NULL,
    p_staff_id      INT         DEFAULT NULL,
    p_client_id     INT         DEFAULT NULL,
    p_status        VARCHAR(30) DEFAULT NULL,
    p_type          VARCHAR(30) DEFAULT NULL,
    p_quantity      INT         DEFAULT NULL,
    p_cost          DECIMAL(10,2) DEFAULT NULL,
    p_paid          BOOL        DEFAULT NULL,
    p_pay_method    VARCHAR(30) DEFAULT NULL,
    p_name          TEXT        DEFAULT NULL,
    p_address       TEXT        DEFAULT NULL,
    p_contact       TEXT        DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE invoice
    SET war_id      = COALESCE(p_war_id,     war_id),
        staff_id    = COALESCE(p_staff_id,   staff_id),
        client_id   = COALESCE(p_client_id,  client_id),
        status      = COALESCE(p_status,     status),
        type        = COALESCE(p_type,       type),
        quantity    = COALESCE(p_quantity,    quantity),
        cost        = COALESCE(p_cost,       cost),
        paid        = COALESCE(p_paid,       paid),
        pay_method  = COALESCE(p_pay_method, pay_method),
        name        = COALESCE(p_name,       name),
        address     = COALESCE(p_address,    address),
        contact     = COALESCE(p_contact,    contact),
        updated_at  = NOW()
    WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice with id % not found', p_id;
    END IF;
END;
$$;


-- 21. sp_delete_invoice
-- Soft-delete an invoice (triggers trg_invoice_soft_delete).
CREATE OR REPLACE PROCEDURE sp_delete_invoice(p_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    -- The BEFORE DELETE trigger converts this into a soft delete
    DELETE FROM invoice WHERE id = p_id;

    -- After the trigger fires, the row still exists — verify the status was set
    IF NOT EXISTS (SELECT 1 FROM invoice WHERE id = p_id AND status = 'cancelled') THEN
        RAISE EXCEPTION 'Invoice with id % not found', p_id;
    END IF;
END;
$$;


-- 22. sp_import_invoices
-- Bulk-import invoices (with optional nested items) from a JSONB array.
CREATE OR REPLACE PROCEDURE sp_import_invoices(p_data JSONB)
LANGUAGE plpgsql
AS $$
DECLARE
    v_rec       JSONB;
    v_item      JSONB;
    v_inv_id    INT;
BEGIN
    FOR v_rec IN SELECT jsonb_array_elements(p_data)
    LOOP
        INSERT INTO invoice (
            war_id, staff_id, client_id,
            status, type, quantity, cost,
            paid, pay_method,
            name, address, contact,
            created_at, updated_at
        ) VALUES (
            (v_rec->>'war_id')::INT,
            (v_rec->>'staff_id')::INT,
            (v_rec->>'client_id')::INT,
            COALESCE(v_rec->>'status', 'pending'),
            v_rec->>'type',
            (v_rec->>'quantity')::INT,
            COALESCE((v_rec->>'cost')::DECIMAL, 0.00),
            COALESCE((v_rec->>'paid')::BOOL, false),
            v_rec->>'pay_method',
            v_rec->>'name',
            v_rec->>'address',
            v_rec->>'contact',
            NOW(), NOW()
        )
        RETURNING id INTO v_inv_id;

        -- If the JSON object has an "items" array, import each item too
        IF v_rec ? 'items' AND jsonb_typeof(v_rec->'items') = 'array' THEN
            FOR v_item IN SELECT jsonb_array_elements(v_rec->'items')
            LOOP
                INSERT INTO invoice_item (
                    inv_id, shipment_type, weight, delivery_speed,
                    quantity, unit_price, total_item_cost,
                    notes, created_at, updated_at
                ) VALUES (
                    v_inv_id,
                    v_item->>'shipment_type',
                    (v_item->>'weight')::DECIMAL,
                    v_item->>'delivery_speed',
                    (v_item->>'quantity')::INT,
                    (v_item->>'unit_price')::DECIMAL,
                    COALESCE((v_item->>'quantity')::INT, 0) * COALESCE((v_item->>'unit_price')::DECIMAL, 0),
                    v_item->>'notes',
                    NOW(), NOW()
                );
            END LOOP;
        END IF;
    END LOOP;

    -- Refresh the materialized view after bulk import
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_invoice_totals;
END;
$$;


/* ---------- INVOICE ITEM ---------- */

-- 23. sp_add_invoice_item
-- Add a single item to an invoice.
-- The trigger will auto-calculate total_item_cost and update the invoice cost.
CREATE OR REPLACE PROCEDURE sp_add_invoice_item(
    p_inv_id          INT,
    p_shipment_type   VARCHAR(50),
    p_weight          DECIMAL(10,2),
    p_delivery_speed  VARCHAR(50),
    p_quantity        INT,
    p_unit_price      DECIMAL(10,2),
    p_notes           TEXT DEFAULT NULL,
    INOUT p_id        INT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Validate that the parent invoice exists
    IF NOT EXISTS (SELECT 1 FROM invoice WHERE id = p_inv_id) THEN
        RAISE EXCEPTION 'Invoice with id % not found', p_inv_id;
    END IF;

    INSERT INTO invoice_item (
        inv_id, shipment_type, weight, delivery_speed,
        quantity, unit_price,
        notes, created_at, updated_at
    ) VALUES (
        p_inv_id, p_shipment_type, p_weight, p_delivery_speed,
        p_quantity, p_unit_price,
        p_notes, NOW(), NOW()
    )
    RETURNING id INTO p_id;

    -- total_item_cost is set by trg_invoice_item_calc_total
    -- invoice.cost is recalculated by trg_invoice_update_cost
END;
$$;


/* ---------- VEHICLE ---------- */

-- 24. sp_create_vehicle
-- Create a new vehicle with validation.
CREATE OR REPLACE PROCEDURE sp_create_vehicle(
    p_vehicle_type          VARCHAR(50),
    p_plate_number          VARCHAR(20),
    p_capacity              DECIMAL(10,2),
    p_brand                 VARCHAR(50),
    p_model                 VARCHAR(50),
    p_vehicle_status        VARCHAR(20),
    p_year                  INT,
    p_fuel_type             VARCHAR(30),
    p_last_maintenance_date DATE DEFAULT NULL,
    INOUT p_id              INT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Validate year
    IF NOT fn_is_valid_year(p_year) THEN
        RAISE EXCEPTION 'Invalid year: %. Must be between 1900 and %.', p_year, EXTRACT(YEAR FROM CURRENT_DATE)::INT + 1;
    END IF;

    INSERT INTO vehicle (
        vehicle_type, plate_number, capacity,
        brand, model, vehicle_status,
        year, fuel_type, last_maintenance_date,
        is_active, created_at, updated_at
    ) VALUES (
        p_vehicle_type, p_plate_number, p_capacity,
        p_brand, p_model, COALESCE(p_vehicle_status, 'available'),
        p_year, p_fuel_type, p_last_maintenance_date,
        true, NOW(), NOW()
    )
    RETURNING id INTO p_id;
END;
$$;


-- 25. sp_update_vehicle
-- Update an existing vehicle's mutable fields.
CREATE OR REPLACE PROCEDURE sp_update_vehicle(
    p_id                     INT,
    p_vehicle_type           VARCHAR(50)    DEFAULT NULL,
    p_plate_number           VARCHAR(20)    DEFAULT NULL,
    p_capacity               DECIMAL(10,2)  DEFAULT NULL,
    p_brand                  VARCHAR(50)    DEFAULT NULL,
    p_model                  VARCHAR(50)    DEFAULT NULL,
    p_vehicle_status         VARCHAR(20)    DEFAULT NULL,
    p_year                   INT            DEFAULT NULL,
    p_fuel_type              VARCHAR(30)    DEFAULT NULL,
    p_last_maintenance_date  DATE           DEFAULT NULL,
    p_is_active              BOOL           DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Validate year if provided
    IF p_year IS NOT NULL AND NOT fn_is_valid_year(p_year) THEN
        RAISE EXCEPTION 'Invalid year: %. Must be between 1900 and %.', p_year, EXTRACT(YEAR FROM CURRENT_DATE)::INT + 1;
    END IF;

    UPDATE vehicle
    SET vehicle_type          = COALESCE(p_vehicle_type,          vehicle_type),
        plate_number          = COALESCE(p_plate_number,          plate_number),
        capacity              = COALESCE(p_capacity,              capacity),
        brand                 = COALESCE(p_brand,                 brand),
        model                 = COALESCE(p_model,                 model),
        vehicle_status        = COALESCE(p_vehicle_status,        vehicle_status),
        year                  = COALESCE(p_year,                  year),
        fuel_type             = COALESCE(p_fuel_type,             fuel_type),
        last_maintenance_date = COALESCE(p_last_maintenance_date, last_maintenance_date),
        is_active             = COALESCE(p_is_active,             is_active),
        updated_at            = NOW()
    WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vehicle with id % not found', p_id;
    END IF;
END;
$$;


-- 26. sp_delete_vehicle
-- Delete a vehicle. Prevents deletion if assigned to active routes.
CREATE OR REPLACE PROCEDURE sp_delete_vehicle(p_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Check for active routes using this vehicle
    IF EXISTS (
        SELECT 1 FROM route
        WHERE vehicle_id = p_id
          AND delivery_status IN ('not_started', 'on_going')
    ) THEN
        RAISE EXCEPTION 'Cannot delete vehicle %: it is assigned to active routes.', p_id;
    END IF;

    DELETE FROM vehicle WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vehicle with id % not found', p_id;
    END IF;
END;
$$;


-- 27. sp_import_vehicles
-- Bulk-import vehicles from a JSONB array.
CREATE OR REPLACE PROCEDURE sp_import_vehicles(p_data JSONB)
LANGUAGE plpgsql
AS $$
DECLARE
    v_rec JSONB;
BEGIN
    FOR v_rec IN SELECT jsonb_array_elements(p_data)
    LOOP
        INSERT INTO vehicle (
            vehicle_type, plate_number, capacity,
            brand, model, vehicle_status,
            year, fuel_type, last_maintenance_date,
            is_active, created_at, updated_at
        ) VALUES (
            v_rec->>'vehicle_type',
            v_rec->>'plate_number',
            (v_rec->>'capacity')::DECIMAL,
            v_rec->>'brand',
            v_rec->>'model',
            COALESCE(v_rec->>'vehicle_status', 'available'),
            (v_rec->>'year')::INT,
            v_rec->>'fuel_type',
            (v_rec->>'last_maintenance_date')::DATE,
            COALESCE((v_rec->>'is_active')::BOOL, true),
            NOW(), NOW()
        );
    END LOOP;
END;
$$;


/* ---------- ROUTE ---------- */

-- 28. sp_create_route
-- Create a new route.
CREATE OR REPLACE PROCEDURE sp_create_route(
    p_driver_id           INT,
    p_vehicle_id          INT,
    p_war_id              INT,
    p_description         TEXT,
    p_delivery_status     VARCHAR(20),
    p_delivery_date       DATE,
    p_delivery_start_time TIMESTAMPTZ DEFAULT NULL,
    p_delivery_end_time   TIMESTAMPTZ DEFAULT NULL,
    p_expected_duration   TIME        DEFAULT NULL,
    p_kms_travelled       DECIMAL(8,2) DEFAULT NULL,
    p_driver_notes        TEXT        DEFAULT NULL,
    INOUT p_id            INT         DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO route (
        driver_id, vehicle_id, war_id,
        description, delivery_status,
        delivery_date, delivery_start_time, delivery_end_time,
        expected_duration, kms_travelled, driver_notes,
        is_active, created_at, updated_at
    ) VALUES (
        p_driver_id, p_vehicle_id, p_war_id,
        p_description, COALESCE(p_delivery_status, 'not_started'),
        p_delivery_date, p_delivery_start_time, p_delivery_end_time,
        p_expected_duration, p_kms_travelled, p_driver_notes,
        true, NOW(), NOW()
    )
    RETURNING id INTO p_id;

    -- trg_route_time_check validates start/end times automatically
END;
$$;


-- 29. sp_update_route
-- Update an existing route's mutable fields.
CREATE OR REPLACE PROCEDURE sp_update_route(
    p_id                   INT,
    p_driver_id            INT            DEFAULT NULL,
    p_vehicle_id           INT            DEFAULT NULL,
    p_war_id               INT            DEFAULT NULL,
    p_description          TEXT           DEFAULT NULL,
    p_delivery_status      VARCHAR(20)    DEFAULT NULL,
    p_delivery_date        DATE           DEFAULT NULL,
    p_delivery_start_time  TIMESTAMPTZ    DEFAULT NULL,
    p_delivery_end_time    TIMESTAMPTZ    DEFAULT NULL,
    p_expected_duration    TIME           DEFAULT NULL,
    p_kms_travelled        DECIMAL(8,2)   DEFAULT NULL,
    p_driver_notes         TEXT           DEFAULT NULL,
    p_is_active            BOOL           DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE route
    SET driver_id           = COALESCE(p_driver_id,           driver_id),
        vehicle_id          = COALESCE(p_vehicle_id,          vehicle_id),
        war_id              = COALESCE(p_war_id,              war_id),
        description         = COALESCE(p_description,         description),
        delivery_status     = COALESCE(p_delivery_status,     delivery_status),
        delivery_date       = COALESCE(p_delivery_date,       delivery_date),
        delivery_start_time = COALESCE(p_delivery_start_time, delivery_start_time),
        delivery_end_time   = COALESCE(p_delivery_end_time,   delivery_end_time),
        expected_duration   = COALESCE(p_expected_duration,   expected_duration),
        kms_travelled       = COALESCE(p_kms_travelled,       kms_travelled),
        driver_notes        = COALESCE(p_driver_notes,        driver_notes),
        is_active           = COALESCE(p_is_active,           is_active),
        updated_at          = NOW()
    WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Route with id % not found', p_id;
    END IF;

    -- trg_route_time_check validates start/end times automatically
END;
$$;


-- 30. sp_delete_route
-- Delete a route. Prevents deletion if it has active deliveries.
CREATE OR REPLACE PROCEDURE sp_delete_route(p_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Check for active deliveries on this route
    IF EXISTS (
        SELECT 1 FROM delivery
        WHERE route_id = p_id
          AND status NOT IN ('completed', 'cancelled')
    ) THEN
        RAISE EXCEPTION 'Cannot delete route %: it has active deliveries.', p_id;
    END IF;

    DELETE FROM route WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Route with id % not found', p_id;
    END IF;
END;
$$;


-- 31. sp_import_routes
-- Bulk-import routes from a JSONB array.
CREATE OR REPLACE PROCEDURE sp_import_routes(p_data JSONB)
LANGUAGE plpgsql
AS $$
DECLARE
    v_rec JSONB;
BEGIN
    FOR v_rec IN SELECT jsonb_array_elements(p_data)
    LOOP
        INSERT INTO route (
            driver_id, vehicle_id, war_id,
            description, delivery_status,
            delivery_date, delivery_start_time, delivery_end_time,
            expected_duration, kms_travelled, driver_notes,
            is_active, created_at, updated_at
        ) VALUES (
            (v_rec->>'driver_id')::INT,
            (v_rec->>'vehicle_id')::INT,
            (v_rec->>'war_id')::INT,
            v_rec->>'description',
            COALESCE(v_rec->>'delivery_status', 'not_started'),
            (v_rec->>'delivery_date')::DATE,
            (v_rec->>'delivery_start_time')::TIMESTAMPTZ,
            (v_rec->>'delivery_end_time')::TIMESTAMPTZ,
            (v_rec->>'expected_duration')::TIME,
            (v_rec->>'kms_travelled')::DECIMAL,
            v_rec->>'driver_notes',
            COALESCE((v_rec->>'is_active')::BOOL, true),
            NOW(), NOW()
        );
    END LOOP;
END;
$$;


/*==============================================================*/
/* END OF rodrigo_objects.sql                                    */
/* Total: 31 SQL blocks (32 objects including unique indexes)   */
/*==============================================================*/
