/*
Purpose:
    Retrieves the complete audit history for a record.

Process:
    Calls audit.primary_key_columns to get the primary key columns.

    Uses audit.to_record_id to convert the input JSON record into a unique record_id.

    Queries the audit.record_version table for all entries matching that record_id.

    Dynamically determines the set of keys present in both the record and old_record JSONB columns.

    Constructs a dynamic SQL query that “pivots” the JSON data—each key becomes two columns:
        A new_<key> column holding the value from the current record.
        An old_<key> column holding the previous value.

    Returns each audit row as a JSONB object (each row is wrapped via row_to_json(... )::jsonb).
*/

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