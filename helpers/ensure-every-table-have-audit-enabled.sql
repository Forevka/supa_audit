-- this script goes over tables in particular schema and attaches triggers for supabase audit
-- comment 23 line if you want dry run

DO $$
DECLARE
    t_table_name text;
BEGIN
    -- Loop through all tables in the 'public' schema
    FOR t_table_name IN
        SELECT table_name as t_table_name
        FROM information_schema.tables
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    LOOP
        -- Check if the audit trigger exists for the current table
        IF NOT EXISTS (
            SELECT 1
            FROM pg_trigger
            WHERE 
                tgname LIKE 'audit_%'
                AND tgrelid::regclass = format('public.%I', t_table_name)::regclass
        ) THEN
            RAISE NOTICE 'No audit triggers found for table: %', t_table_name;
            PERFORM audit.enable_tracking(format('public.%I', t_table_name)::regclass);
            RAISE NOTICE 'Audit triggers attached for table: %', t_table_name;
        ELSE
            RAISE NOTICE 'Audit triggers already exist for table: %', t_table_name;
        END IF;
    END LOOP;
END $$;
