-- This program is open source, licensed under the PostgreSQL License.
-- For license terms, see the LICENSE file.
--
-- Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION opm_core" to load this file. \quit

CREATE OR REPLACE
FUNCTION public.opm_check_dropped_extensions()
RETURNS event_trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_schema text;
BEGIN
    WITH del AS (
        DELETE FROM public.api a
        USING pg_event_trigger_dropped_objects() d
        WHERE d.schema_name LIKE 'wh_%' ESCAPE '|'
        AND d.object_type = 'function'
        AND d.objid::regprocedure = a.proc
        RETURNING d.schema_name
    )
    SELECT string_agg(DISTINCT schema_name,',') INTO v_schema
    FROM del ;
    IF v_schema IS NOT NULL THEN
        RAISE NOTICE 'OPM: DROP EXTENSION intercepted, functions from % have been removed from the available API.', v_schema ;
    END IF ;
END;
$$ ;

REVOKE ALL ON FUNCTION public.opm_check_dropped_extensions() FROM public ;

COMMENT ON FUNCTION public.opm_check_dropped_extensions() IS
'Clean public.api table if an OPM warehouse is dropped.' ;

CREATE EVENT TRIGGER opm_check_dropped_extensions
  ON sql_drop
  WHEN tag IN ('DROP EXTENSION')
  EXECUTE PROCEDURE public.opm_check_dropped_extensions() ;



-- This line must be the last one, so that every functions are owned
-- by the database owner
SELECT * FROM public.set_extension_owner('opm_core');
