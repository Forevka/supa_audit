-- this function takes two similar jsonb and compares them key by key


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
