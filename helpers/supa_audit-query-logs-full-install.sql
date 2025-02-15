-- This cumulative file contains all necessary functions to perform query over audit.record_version logs stored by supa_audit 
-- You can run following files in the order specified in their names to achieve similar installation process:
--      supa_audit-quesy-logs-1-jsonb-diff
--      supa_audit-query-logs-2-get-record-history
--      supa_audit-query-logs-3-get-record-history-diff


CREATE OR REPLACE FUNCTION audit.get_record_history(
    p_entity_oid oid,
    p_rec        jsonb
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    pkey_cols   "pg_catalog"."_text";
    rec_id      "pg_catalog"."uuid";
    keys        text[];
    key         text;
    columns_sql text := '';
    final_sql   text;
BEGIN
    -- 1. Get the primary key columns for the entity
    pkey_cols := audit.primary_key_columns(p_entity_oid);

    -- 2. Convert the incoming JSON record into a record_id
    rec_id := audit.to_record_id(p_entity_oid, pkey_cols, p_rec);

    IF rec_id IS NULL THEN
        RAISE NOTICE 'Record id could not be determined from input JSON';
        RETURN;
    END IF;

    -- 3. Gather distinct JSON keys from both "record" and "old_record" for this record id
    SELECT array_agg(DISTINCT t.json_key)
    INTO keys
    FROM (
         SELECT jsonb_object_keys(record) AS json_key
         FROM audit.record_version
         WHERE record_id = rec_id
         UNION
         SELECT jsonb_object_keys(old_record) AS json_key
         FROM audit.record_version
         WHERE record_id = rec_id AND old_record IS NOT NULL
    ) t;

    IF keys IS NULL THEN
        RAISE NOTICE 'No JSON keys found for record id %', rec_id;
    END IF;

    -- 4. Build the dynamic column list. For each key, extract:
    --    - new value from "record" as new_<key>
    --    - old value from "old_record" as old_<key>
    FOREACH key IN ARRAY keys LOOP
        columns_sql := columns_sql ||
            format(', record ->> %L AS new_%I', key, key) ||
            format(', old_record ->> %L AS old_%I', key, key);
    END LOOP;

    -- 5. Build the final SQL.
    --    We wrap the SELECT in a subquery and use row_to_json() to return a JSONB row.
    final_sql := 'SELECT row_to_json(t)::jsonb as js FROM (' ||
                 'SELECT id, record_id, op, ts, table_schema, table_name' ||
                 columns_sql ||
                 ' FROM audit.record_version WHERE record_id = ' || quote_literal(rec_id) ||
                 ') t';

    RAISE NOTICE 'Executing dynamic SQL: %', final_sql;

    RETURN QUERY EXECUTE final_sql;
END;
$$;

CREATE OR REPLACE FUNCTION audit.jsonb_diff(old jsonb, new jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    r_key text;
    diff jsonb := '{}'::jsonb;
    old_val text;
    new_val text;
BEGIN
    FOR r_key IN
        SELECT DISTINCT s.json_key
        FROM (
             SELECT jsonb_object_keys(old) AS json_key
             UNION
             SELECT jsonb_object_keys(new) AS json_key
        ) s
    LOOP
        old_val := old ->> r_key;
        new_val := new ->> r_key;
        IF old_val IS DISTINCT FROM new_val THEN
             diff := diff || jsonb_build_object(r_key, jsonb_build_object('old', old_val, 'new', new_val));
        END IF;
    END LOOP;
    RETURN diff;
END;
$$;

CREATE OR REPLACE FUNCTION audit.get_record_history_diff(
    p_entity_oid oid,
    p_rec        jsonb,
    p_include_initial_data boolean DEFAULT false
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    rec      jsonb;
    prev_rec jsonb := NULL;
    diff     jsonb;
    rec_key  text;
    base_key text;
    new_val  text;
    old_val  text;
BEGIN
    FOR rec IN
       SELECT t
       FROM audit.get_record_history(p_entity_oid, p_rec) AS t
       ORDER BY (t->>'ts')::timestamp
    LOOP
       IF prev_rec IS NULL THEN
          IF p_include_initial_data THEN
             diff := '{}'::jsonb;
             FOR rec_key IN
               SELECT key
               FROM jsonb_object_keys(rec) AS key
               WHERE key LIKE 'new_%'
             LOOP
                base_key := substring(rec_key from 5);
                diff := diff || jsonb_build_object(base_key, jsonb_build_object('old', NULL, 'new', rec ->> rec_key));
             END LOOP;
             diff := diff || jsonb_build_object('ts', jsonb_build_object('old', NULL, 'new', rec ->> 'ts'));
             RETURN NEXT diff;
          END IF;
          prev_rec := rec;
          CONTINUE;
       END IF;

       diff := '{}'::jsonb;
       FOR rec_key IN
         SELECT key
         FROM jsonb_object_keys(rec) AS key
         WHERE key LIKE 'new_%'
       LOOP
         base_key := substring(rec_key from 5);
         new_val := rec ->> rec_key;
         old_val := rec ->> ('old_' || base_key);
         IF new_val IS DISTINCT FROM old_val THEN
            diff := diff || jsonb_build_object(base_key, jsonb_build_object('old', old_val, 'new', new_val));
         END IF;
       END LOOP;

       IF (prev_rec->>'ts') IS DISTINCT FROM (rec->>'ts') THEN
         diff := diff || jsonb_build_object('ts', jsonb_build_object('old', prev_rec->>'ts', 'new', rec->>'ts'));
       END IF;

       IF diff <> '{}'::jsonb THEN
         RETURN NEXT diff;
       END IF;
       prev_rec := rec;
    END LOOP;
    RETURN;
END;
$$;