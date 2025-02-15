/*
Purpose:
    Returns only the differences (diffs) between successive versions of a record.
Process:
    Calls audit.get_record_history to retrieve the pivoted history for the record.

    Orders the audit rows by their timestamp (ts).

    Iterates through the history:

    For each audit row (except the first), it compares every pivoted field (those with the new_ prefix) to determine if its value has changed compared to the previous version.

    Constructs a JSONB diff object that contains only the keys where a change occurred.

    For each changed key, the output includes an object with:
        "old": the previous value.
        "new": the current value.

    If the include_initial_data flag is set to true, the function outputs a baseline record (with all initial values) as the first diff (using NULL for all “old” values).

    Returns one JSONB object per change, thereby allowing users to easily see what has changed over time.
*/

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