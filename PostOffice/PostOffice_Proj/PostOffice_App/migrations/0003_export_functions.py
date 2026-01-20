from django.db import migrations

class Migration(migrations.Migration):

    dependencies = [
        ("PostOffice_App", "0002_triggers_integracion"),
    ]

    operations = [
        migrations.RunSQL(
            """
            ----------------------------------------------------------
            --  DROP PREVIOUS CSV EXPORT FUNCTIONS (if any)
            ----------------------------------------------------------
            DROP FUNCTION IF EXISTS export_warehouses_csv() CASCADE;
            DROP FUNCTION IF EXISTS export_vehicles_csv() CASCADE;
            DROP FUNCTION IF EXISTS export_routes_csv() CASCADE;
            DROP FUNCTION IF EXISTS export_deliveries_csv() CASCADE;
            DROP FUNCTION IF EXISTS export_invoices_csv() CASCADE;


            ----------------------------------------------------------
            --  WAREHOUSES CSV EXPORT
            ----------------------------------------------------------
            CREATE OR REPLACE FUNCTION export_warehouses_csv()
            RETURNS TABLE(line TEXT)
            LANGUAGE plpgsql AS $$
            BEGIN
                RETURN QUERY
                SELECT CONCAT_WS(',',
                    id,
                    name,
                    address,
                    contact,
                    po_schedule_open,
                    po_schedule_close,
                    maximum_storage_capacity
                )
                FROM "PostOffice_App_warehouse"
                ORDER BY id;
            END;
            $$;


            ----------------------------------------------------------
            --  VEHICLES CSV EXPORT
            ----------------------------------------------------------
            CREATE OR REPLACE FUNCTION export_vehicles_csv()
            RETURNS TABLE(line TEXT)
            LANGUAGE plpgsql AS $$
            BEGIN
                RETURN QUERY
                SELECT CONCAT_WS(',',
                    id,
                    plate_number,
                    brand,
                    model,
                    capacity,
                    vehicle_status,
                    year,
                    fuel_type,
                    last_maintenance_date,
                    vehicle_type
                )
                FROM "PostOffice_App_vehicle"
                ORDER BY id;
            END;
            $$;


            ----------------------------------------------------------
            --  ROUTES CSV EXPORT
            ----------------------------------------------------------
            CREATE OR REPLACE FUNCTION export_routes_csv()
            RETURNS TABLE(line TEXT)
            LANGUAGE plpgsql AS $$
            BEGIN
                RETURN QUERY
                SELECT CONCAT_WS(',',
                    id,
                    description,
                    delivery_status,
                    vehicle_id,
                    driver_id,
                    origin_name,
                    origin_address,
                    origin_contact,
                    destination_name,
                    destination_address,
                    destination_contact,
                    delivery_date,
                    delivery_start_time,
                    delivery_end_time,
                    kms_travelled,
                    expected_duration,
                    driver_notes
                )
                FROM "PostOffice_App_route"
                ORDER BY id;
            END;
            $$;


            ----------------------------------------------------------
            --  DELIVERIES CSV EXPORT
            ----------------------------------------------------------
            CREATE OR REPLACE FUNCTION export_deliveries_csv()
            RETURNS TABLE(line TEXT)
            LANGUAGE plpgsql AS $$
            BEGIN
                RETURN QUERY
                SELECT CONCAT_WS(',',
                    id,
                    tracking_number,
                    description,
                    sender_name,
                    sender_address,
                    sender_phone,
                    sender_email,
                    recipient_name,
                    recipient_address,
                    recipient_phone,
                    recipient_email,
                    item_type,
                    weight,
                    dimensions,
                    status,
                    priority,
                    registered_at,
                    updated_at,
                    in_transition,
                    destination,
                    delivery_date,
                    driver_id,
                    invoice_id,
                    route_id,
                    client_id
                )
                FROM "PostOffice_App_delivery"
                ORDER BY id;
            END;
            $$;


            ----------------------------------------------------------
            --  INVOICES CSV EXPORT (FINAL, SINGLE VERSION)
            ----------------------------------------------------------
            CREATE OR REPLACE FUNCTION export_invoices_csv()
            RETURNS TABLE(line TEXT)
            LANGUAGE plpgsql AS $$
            BEGIN
                RETURN QUERY
                SELECT CONCAT_WS(',',
                    id_invoice,
                    invoice_status,
                    invoice_type,
                    quantity,
                    invoice_datetime,
                    cost,
                    paid,
                    payment_method,
                    name,
                    address,
                    contact,
                    user_id
                )
                FROM "PostOffice_App_invoice"
                ORDER BY id_invoice;
            END;
            $$;

            """
        )
    ]
