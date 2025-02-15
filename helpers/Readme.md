## Overview
To facilitate analysis and restoration of changes, a series of functions are provided that:

1. dentify the primary key columns for a given entity. (PROVIDED BY SUPA_AUDIT)
2. Generate a unique record identifier (record_id) from a JSON representation of a record. (PROVIDED BY SUPA_AUDIT)
3. Retrieve the audit log history for that record.
4. Compute and return only the differences (or “diffs”) between successive versions of the record.

## Function Chain and Descriptions
### audit.get_record_history(entity_oid oid, rec jsonb)
**Purpose:**
Retrieves the complete audit history for a record.

**Process:**
Calls audit.primary_key_columns to get the primary key columns.
Uses audit.to_record_id to convert the input JSON record into a unique record_id.
Queries the audit.record_version table for all entries matching that record_id.
Dynamically determines the set of keys present in both the record and old_record JSONB columns.
Constructs a dynamic SQL query that “pivots” the JSON data—each key becomes two columns:
A new_<key> column holding the value from the current record.
An old_<key> column holding the previous value.
Returns each audit row as a JSONB object (each row is wrapped via row_to_json(... )::jsonb).
Usage:
This is the foundational function that retrieves the raw audit data in a pivoted JSON format.

### audit.get_record_history_diff(entity_oid oid, rec jsonb, include_initial_data boolean DEFAULT false)
**Purpose:**
Returns only the differences (diffs) between successive versions of a record.
**Process:**
Orders the audit rows by their timestamp (ts).
Iterates through the history:
For each audit row (except the first), it compares every pivoted field (those with the new_ prefix) to determine if its value has changed compared to the previous version.
Constructs a JSONB diff object that contains only the keys where a change occurred.
For each changed key, the output includes an object with:
"old": the previous value.
"new": the current value.
If the include_initial_data flag is set to true, the function outputs a baseline record (with all initial values) as the first diff (using NULL for all “old” values).
Returns one JSONB object per change, thereby allowing users to easily see what has changed over time.
Usage:
This function is ideal for change tracking and review. Users can call it to obtain a compact history of changes without manually comparing entire records.
How They Work Together
Initial Identification:
The chain starts with audit.primary_key_columns and audit.to_record_id, which work together to determine which record to analyze.

## History Retrieval:
- audit.get_record_history then queries the audit log (audit.record_version) for all entries related to that record. It dynamically pivots the JSON data so that each audit entry is returned with separate columns for the new and old values.

- Diff Computation: audit.get_record_history_diff processes the pivoted history data to compute differences between each consecutive version. If desired, the initial baseline state can also be returned. This function makes it easier for users to see only the changes between versions.

## Usage Examples
Users table DDL:
```sql
```

I've ommited data insertion/updates for brevity

Retrieve Full History (Pivoted JSON):

```sql
SELECT * FROM audit.get_record_history(17318::oid, '{"id": 6}'::jsonb);
```

The result:
```json
{"id": 1, "op": "UPDATE", "ts": "2024-10-04T10:27:09.254176+00:00", "new_id": "6", "old_id": "6", "new_email": "bl@devcom.com", "old_email": "bl@devcom.com", "record_id": "6abba0cb-a814-5ccd-ad88-86cae70986bd", "table_name": "Users", "new_role_id": "1", "old_role_id": "1", "table_schema": "public", "new_last_name": "l", "new_tenant_id": "1", "old_last_name": "l", "old_tenant_id": "1", "new_first_name": "bohdan3", "new_is_blocked": "false", "old_first_name": "bohdan2", "old_is_blocked": "false", "new_password_hash": "QrObR/+fEF6v49u/hNTpmZkH9Nc3cyMp0XwESxFgG98=", "old_password_hash": "QrObR/+fEF6v49u/hNTpmZkH9Nc3cyMp0XwESxFgG98=", "new_is_password_set": "false", "old_is_password_set": "false", "new_created_datetime": "2024-10-02T15:03:55.154947", "old_created_datetime": "2024-10-02T15:03:55.154947", "new_modified_datetime": null, "old_modified_datetime": null, "new_is_email_confirmed": "true", "old_is_email_confirmed": "true"}
{"id": 43, "op": "UPDATE", "ts": "2024-10-08T07:40:02.088688+00:00", "new_id": "6", "old_id": "6", "new_email": "bl.va@devcom.com", "old_email": "bl@devcom.com", "record_id": "6abba0cb-a814-5ccd-ad88-86cae70986bd", "table_name": "Users", "new_role_id": "1", "old_role_id": "1", "table_schema": "public", "new_last_name": "l", "new_tenant_id": "1", "old_last_name": "l", "old_tenant_id": "1", "new_first_name": "bohdan3", "new_is_blocked": "false", "old_first_name": "bohdan3", "old_is_blocked": "false", "new_password_hash": "QrObR/+fEF6v49u/hNTpmZkH9Nc3cyMp0XwESxFgG98=", "old_password_hash": "QrObR/+fEF6v49u/hNTpmZkH9Nc3cyMp0XwESxFgG98=", "new_is_password_set": "false", "old_is_password_set": "false", "new_created_datetime": "2024-10-02T15:03:55.154947", "old_created_datetime": "2024-10-02T15:03:55.154947", "new_modified_datetime": null, "old_modified_datetime": null, "new_is_email_confirmed": "true", "old_is_email_confirmed": "true"}
{"id": 44, "op": "UPDATE", "ts": "2024-10-08T07:40:09.503683+00:00", "new_id": "6", "old_id": "6", "new_email": "bl.va@devcom.com", "old_email": "bl.va@devcom.com", "record_id": "6abba0cb-a814-5ccd-ad88-86cae70986bd", "table_name": "Users", "new_role_id": "2", "old_role_id": "1", "table_schema": "public", "new_last_name": "l", "new_tenant_id": "1", "old_last_name": "l", "old_tenant_id": "1", "new_first_name": "bohdan3", "new_is_blocked": "false", "old_first_name": "bohdan3", "old_is_blocked": "false", "new_password_hash": "QrObR/+fEF6v49u/hNTpmZkH9Nc3cyMp0XwESxFgG98=", "old_password_hash": "QrObR/+fEF6v49u/hNTpmZkH9Nc3cyMp0XwESxFgG98=", "new_is_password_set": "false", "old_is_password_set": "false", "new_created_datetime": "2024-10-02T15:03:55.154947", "old_created_datetime": "2024-10-02T15:03:55.154947", "new_modified_datetime": null, "old_modified_datetime": null, "new_is_email_confirmed": "true", "old_is_email_confirmed": "true"}
{"id": 57, "op": "UPDATE", "ts": "2024-10-08T15:05:55.743479+00:00", "new_id": "6", "old_id": "6", "new_email": "bl.va@devcom.com", "old_email": "bl.va@devcom.com", "record_id": "6abba0cb-a814-5ccd-ad88-86cae70986bd", "table_name": "Users", "new_role_id": "2", "old_role_id": "2", "table_schema": "public", "new_last_name": "l", "new_tenant_id": "1", "old_last_name": "l", "old_tenant_id": "1", "new_first_name": "bohdan3", "new_is_blocked": "false", "old_first_name": "bohdan3", "old_is_blocked": "false", "new_password_hash": "QrObR/+fEF6v49u/hNTpmZkH9Nc3cyMp0XwESxFgG98=", "old_password_hash": "QrObR/+fEF6v49u/hNTpmZkH9Nc3cyMp0XwESxFgG98=", "new_is_password_set": "true", "old_is_password_set": "false", "new_created_datetime": "2024-10-02T15:03:55.154947", "old_created_datetime": "2024-10-02T15:03:55.154947", "new_modified_datetime": null, "old_modified_datetime": null, "new_is_email_confirmed": "true", "old_is_email_confirmed": "true"}
{"id": 189153, "op": "UPDATE", "ts": "2025-02-14T17:18:41.925637+00:00", "new_id": "6", "old_id": "6", "new_email": "bl.va+2@devcom.com", "old_email": "bl.va@devcom.com", "record_id": "6abba0cb-a814-5ccd-ad88-86cae70986bd", "table_name": "Users", "new_role_id": "2", "old_role_id": "2", "table_schema": "public", "new_last_name": "l", "new_tenant_id": "1", "old_last_name": "l", "old_tenant_id": "1", "new_first_name": "bohdan33", "new_is_blocked": "false", "old_first_name": "bohdan3", "old_is_blocked": "false", "new_password_hash": "QrObR/+fEF6v49u/hNTpmZkH9Nc3cyMp0XwESxFgG98=", "old_password_hash": "QrObR/+fEF6v49u/hNTpmZkH9Nc3cyMp0XwESxFgG98=", "new_is_password_set": "true", "old_is_password_set": "true", "new_created_datetime": "2024-10-02T15:03:55.154947", "old_created_datetime": "2024-10-02T15:03:55.154947", "new_modified_datetime": null, "old_modified_datetime": null, "new_is_email_confirmed": "true", "old_is_email_confirmed": "true"}
```

So, as you can see there is full log with changes with 'new_' and 'old_' properties for easier parsing data.

Retrieve Only Changes (Diffs) with Initial Baseline (this one may be useful in systems that uses event sourcing to restore current state of an entity):
```sql
SELECT * FROM audit.get_record_history_diff(17318::oid, '{"id": 6}'::jsonb, true);
```

Result:
```json
{"id": {"new": "6", "old": null}, "ts": {"new": "2024-10-04T10:27:09.254176+00:00", "old": null}, "email": {"new": "bl@devcom.com", "old": null}, "role_id": {"new": "1", "old": null}, "last_name": {"new": "l", "old": null}, "tenant_id": {"new": "1", "old": null}, "first_name": {"new": "bohdan3", "old": null}, "is_blocked": {"new": "false", "old": null}, "password_hash": {"new": "QrObR/+fEF6v49u/hNTpmZkH9Nc3cyMp0XwESxFgG98=", "old": null}, "is_password_set": {"new": "false", "old": null}, "created_datetime": {"new": "2024-10-02T15:03:55.154947", "old": null}, "modified_datetime": {"new": null, "old": null}, "is_email_confirmed": {"new": "true", "old": null}}
{"ts": {"new": "2024-10-08T07:40:02.088688+00:00", "old": "2024-10-04T10:27:09.254176+00:00"}, "email": {"new": "bl.va@devcom.com", "old": "bl@devcom.com"}}
{"ts": {"new": "2024-10-08T07:40:09.503683+00:00", "old": "2024-10-08T07:40:02.088688+00:00"}, "role_id": {"new": "2", "old": "1"}}
{"ts": {"new": "2024-10-08T15:05:55.743479+00:00", "old": "2024-10-08T07:40:09.503683+00:00"}, "is_password_set": {"new": "true", "old": "false"}}
{"ts": {"new": "2025-02-14T17:18:41.925637+00:00", "old": "2025-01-13T10:54:02.26464+00:00"}, "email": {"new": "bl.va+2@devcom.com", "old": "bl.va@devcom.com"}, "first_name": {"new": "bohdan33", "old": "bohdan3"}}
```

So, using this logs you can restore any event/entity.