from django.db import migrations

class Migration(migrations.Migration):

    dependencies = [
        ('PostOffice_App', '0001_initial'),
    ]

    operations = [
        migrations.RunSQL(
            """
            -- DROP ALL TRIGGERS 
            
            DROP TRIGGER IF EXISTS trg_update_delivery_timestamp ON "PostOffice_App_delivery";
            DROP TRIGGER IF EXISTS trg_delivery_created ON "PostOffice_App_delivery";
            DROP TRIGGER IF EXISTS trg_status_change ON "PostOffice_App_delivery";
            DROP TRIGGER IF EXISTS trg_validate_delivery ON "PostOffice_App_delivery";

            DROP TRIGGER IF EXISTS trg_validate_invoice ON "PostOffice_App_invoice";
            DROP TRIGGER IF EXISTS trg_validate_driver ON "PostOffice_App_employeedriver";
            DROP TRIGGER IF EXISTS trg_route_completed ON "PostOffice_App_route";


            -- DROP FUNCTIONS 
            
            DROP FUNCTION IF EXISTS fn_update_delivery_timestamp() CASCADE;
            DROP FUNCTION IF EXISTS fn_log_delivery_created() CASCADE;
            DROP FUNCTION IF EXISTS fn_log_delivery_status_change() CASCADE;
            DROP FUNCTION IF EXISTS fn_validate_delivery() CASCADE;
            DROP FUNCTION IF EXISTS fn_validate_invoice() CASCADE;
            DROP FUNCTION IF EXISTS fn_validate_driver() CASCADE;
            DROP FUNCTION IF EXISTS fn_route_status() CASCADE;


            -- FUNCTION: update timestamp for delivery
            
            CREATE OR REPLACE FUNCTION fn_update_delivery_timestamp()
            RETURNS TRIGGER AS $$
            BEGIN
                NEW.updated_at = CURRENT_TIMESTAMP;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER trg_update_delivery_timestamp
            BEFORE UPDATE ON "PostOffice_App_delivery"
            FOR EACH ROW
            EXECUTE FUNCTION fn_update_delivery_timestamp();


            -- FUNCTION: log delivery created

            CREATE OR REPLACE FUNCTION fn_log_delivery_created()
            RETURNS TRIGGER AS $$
            BEGIN
                RAISE NOTICE 'Delivery % created with status %', NEW.id, NEW.status;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER trg_delivery_created
            AFTER INSERT ON "PostOffice_App_delivery"
            FOR EACH ROW
            EXECUTE FUNCTION fn_log_delivery_created();


            -- FUNCTION: log status change

            CREATE OR REPLACE FUNCTION fn_log_delivery_status_change()
            RETURNS TRIGGER AS $$
            BEGIN
                IF NEW.status IS DISTINCT FROM OLD.status THEN
                    RAISE NOTICE 'Delivery % changed status from % to %', NEW.id, OLD.status, NEW.status;
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER trg_status_change
            AFTER UPDATE ON "PostOffice_App_delivery"
            FOR EACH ROW
            EXECUTE FUNCTION fn_log_delivery_status_change();


            -- FUNCTION: validate delivery

            CREATE OR REPLACE FUNCTION fn_validate_delivery()
            RETURNS TRIGGER AS $$
            BEGIN
                IF NEW.status = 'Completed' AND NEW.delivery_date IS NULL THEN
                    RAISE EXCEPTION 'Cannot mark delivery as Completed without delivery_date';
                END IF;

                IF NEW.weight <= 0 THEN
                    RAISE EXCEPTION 'Weight must be greater than 0';
                END IF;

                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER trg_validate_delivery
            BEFORE INSERT OR UPDATE ON "PostOffice_App_delivery"
            FOR EACH ROW
            EXECUTE FUNCTION fn_validate_delivery();


            -- FUNCTION: validate invoice

            CREATE OR REPLACE FUNCTION fn_validate_invoice()
            RETURNS TRIGGER AS $$
            BEGIN
                IF NEW.cost < 0 THEN
                    RAISE EXCEPTION 'Invoice cost cannot be negative';
                END IF;

                IF NEW.quantity IS NOT NULL AND NEW.quantity <= 0 THEN
                    RAISE EXCEPTION 'Invoice quantity must be greater than zero';
                END IF;

                IF NEW.paid = TRUE THEN
                    NEW.invoice_status = 'Paid';
                END IF;

                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER trg_validate_invoice
            BEFORE INSERT OR UPDATE ON "PostOffice_App_invoice"
            FOR EACH ROW
            EXECUTE FUNCTION fn_validate_invoice();

            
            -- FUNCTION: validate driver

            CREATE OR REPLACE FUNCTION fn_validate_driver()
            RETURNS TRIGGER AS $$
            BEGIN
                IF NEW.license_expiry_date < CURRENT_DATE THEN
                    RAISE EXCEPTION 'Driver license expired';
                END IF;

                IF NEW.driving_experience_years < 0 THEN
                    RAISE EXCEPTION 'Driving experience cannot be negative';
                END IF;

                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER trg_validate_driver
            BEFORE INSERT OR UPDATE ON "PostOffice_App_employeedriver"
            FOR EACH ROW
            EXECUTE FUNCTION fn_validate_driver();

            
            -- FUNCTION: route completed → update deliveries

            CREATE OR REPLACE FUNCTION fn_route_status()
            RETURNS TRIGGER AS $$
            BEGIN
                IF NEW.delivery_status = 'Completed' THEN
                    UPDATE "PostOffice_App_delivery"
                    SET status='Completed', delivery_date = CURRENT_DATE
                    WHERE route_id = NEW.id;
                END IF;

                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER trg_route_completed
            AFTER UPDATE ON "PostOffice_App_route"
            FOR EACH ROW
            EXECUTE FUNCTION fn_route_status();
            """
        ),
    ]
