-- This program is open source, licensed under the PostgreSQL License.
-- For license terms, see the LICENSE file.
--
-- Copyright (C) 2012-2020: Open PostgreSQL Monitoring Development Group

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION opm_core" to load this file. \quit

ALTER TABLE public.api
ALTER COLUMN proc TYPE text
USING (pg_identify_object('pg_catalog.pg_proc'::regclass, proc, 0)).identity;

CREATE OR REPLACE FUNCTION public.register_api(IN p_proc regprocedure,
    OUT proc regprocedure, OUT registered boolean)
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF
SET search_path TO pg_catalog
AS $$
DECLARE
    v_ok boolean ;
BEGIN
    SELECT COUNT(*) = 0 INTO v_ok
    FROM public.api
    WHERE api.proc = (pg_catalog.pg_identify_object('pg_catalog.pg_proc'::regclass, p_proc, 0)).identity::text;

    IF NOT v_ok THEN
        register_api.proc := p_proc ;
        register_api.registered := false ;
        RETURN ;
    END IF ;

    INSERT INTO public.api VALUES ((pg_catalog.pg_identify_object('pg_catalog.pg_proc'::regclass, p_proc, 0)).identity )
    RETURNING p_proc, true
        INTO register_api.proc, register_api.registered;
END
$$;

CREATE OR REPLACE
FUNCTION public.opm_check_dropped_extensions()
RETURNS event_trigger
LANGUAGE plpgsql
SET search_path TO public
AS $$
DECLARE
    v_schema text;
BEGIN
    WITH del AS (
        DELETE FROM public.api a
        USING pg_event_trigger_dropped_objects() d
        WHERE d.schema_name LIKE 'wh_%' ESCAPE '|'
        AND d.object_type = 'function'
        AND d.object_identity = a.proc
        RETURNING d.schema_name
    )
    SELECT string_agg(DISTINCT schema_name,',') INTO v_schema
    FROM del ;
    IF v_schema IS NOT NULL THEN
        RAISE NOTICE 'OPM: DROP EXTENSION intercepted, functions from % have been removed from the available API.', v_schema ;
    END IF ;
END;
$$ ;
