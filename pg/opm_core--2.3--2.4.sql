-- This program is open source, licensed under the PostgreSQL License.
-- For license terms, see the LICENSE file.
--
-- Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION opm_core" to load this file. \quit

/*
 * this function is only called by the extensions themselves
 *  to set the owner of their functions to the database owner.
 */
CREATE OR REPLACE
FUNCTION public.set_extension_owner(IN p_extname name)
RETURNS TABLE (owner name, objtype text, objname text)
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF
SET search_path TO public
AS $$
DECLARE
    v_nspname name := n.nspname
        FROM pg_extension AS e
            JOIN pg_namespace AS n ON e.extnamespace = n.oid
        WHERE e.extname = p_extname;
BEGIN
    owner := r.rolname FROM pg_database AS d
        JOIN pg_roles AS r ON d.datdba = r.oid
        WHERE datname = pg_catalog.current_database();

    FOR objtype, objname IN (
        SELECT i.type, i.identity
        FROM pg_catalog.pg_depend AS d
            JOIN pg_catalog.pg_extension AS e ON d.refobjid = e.oid,
            LATERAL pg_catalog.pg_identify_object(d.classid, d.objid, 0) AS i
        WHERE e.extname = p_extname
            AND d.refclassid = 'pg_catalog.pg_extension'::pg_catalog.regclass
            AND deptype = 'e'
            -- exclude this function. It always needs to belong to a superuser.
            AND i.identity !~ '^public.set_extension_owner'
            -- exclude event trigger. They always need to belong to a superuser.
            AND i.type != 'event trigger'
        ORDER BY 1 DESC
    )
    LOOP
        -- warning: identity is already escaped by pg_identify_object(...)
        EXECUTE pg_catalog.format('ALTER %s %s OWNER TO %I', objtype, objname, owner);
        RETURN NEXT;
    END LOOP;

    EXECUTE pg_catalog.format('ALTER SCHEMA %I OWNER TO %I', v_nspname, owner);
    objtype := 'schema';
    objname := CAST (v_nspname AS text);

    RETURN NEXT;
END
$$;

REVOKE ALL ON FUNCTION public.set_extension_owner(IN name) FROM public;

COMMENT ON FUNCTION public.set_extension_owner(name) IS
'this function is only called by the extensions themselves to set the owner of their functions to the database owner.';

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

CREATE OR REPLACE
FUNCTION public.create_graph_for_new_metric(IN p_server_id bigint,
    OUT rc boolean)
LANGUAGE plpgsql STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_owner    bigint;
  metricsrow record;
  graphsrow  record;
BEGIN

    rc := false;

    --Does the server exists ?
    SELECT id_role INTO v_owner
    FROM public.servers AS s
    WHERE s.id = p_server_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Server unknown or not allowed for current user.';
    END IF;

  -- Is the user allowed to create graphs ?
    IF NOT (public.is_admin() OR public.is_member(v_owner)) THEN
        RAISE EXCEPTION 'Server unknown or not allowed for current user.';
    END IF;

  FOR metricsrow IN (
    SELECT DISTINCT s.service, s.warehouse, m.id_service, COALESCE(m.unit,'') AS unit
    FROM public.services s
    JOIN public.metrics m ON s.id = m.id_service
    WHERE s.id_server = p_server_id
        AND NOT EXISTS (
            SELECT 1 FROM public.series gs
            JOIN public.metrics m2 ON m2.id=gs.id_metric
            WHERE m2.id=m.id
        )
    )
  LOOP
    -- how many graph existing for the ungraphed serie
    SELECT COUNT(DISTINCT id_graph) as nb, min(id_graph) AS id_graph INTO graphsrow
    FROM public.services s1
    JOIN public.metrics m ON m.id_service = s1.id
    JOIN public.series s2 ON s2.id_metric = m.id
    JOIN public.graphs g ON g.id = s2.id_graph
    WHERE s1.id = metricsrow.id_service
    AND COALESCE(m.unit, '') = 's';

    IF (graphsrow.nb != 1) THEN
        -- already multiple graphs or no graph, let's create a new one
        EXECUTE format('WITH new_graphs (id_graph) AS (
              INSERT INTO public.graphs (graph, config)
                VALUES (%L || '' ('' || CASE WHEN %L = '''' THEN ''no unit'' ELSE ''in '' || %2$L END || '')'', ''{"type": "lines"}'')
                RETURNING graphs.id
            )
            INSERT INTO %I.series (id_graph, id_metric)
              SELECT new_graphs.id_graph, m.id
              FROM new_graphs
              CROSS JOIN public.metrics m
              WHERE m.id_service = %s
                AND COALESCE(m.unit,'''') = %2$L
                AND NOT EXISTS (
                    SELECT 1
                    FROM public.series gs
                        JOIN public.metrics m2 ON m2.id=gs.id_metric
                    WHERE m2.id=m.id
                )',
        metricsrow.service, metricsrow.unit, metricsrow.warehouse, metricsrow.id_service) ;
    ELSE
        -- exactly 1 graph, add the serie to it
        EXECUTE format('WITH new_graphs (id_graph) AS (
              SELECT %s
            )
            INSERT INTO %I.series (id_graph, id_metric)
              SELECT new_graphs.id_graph, m.id
              FROM new_graphs
              CROSS JOIN public.metrics m
              WHERE m.id_service = %s
                AND COALESCE(m.unit,'''') = %L
                AND NOT EXISTS (
                    SELECT 1
                    FROM public.series gs
                        JOIN public.metrics m2 ON m2.id=gs.id_metric
                    WHERE m2.id=m.id
                )',
        graphsrow.id_graph, metricsrow.warehouse, metricsrow.id_service, metricsrow.unit) ;
    END IF;
  END LOOP;
  rc := true;
END
$$;

REVOKE ALL ON FUNCTION public.create_graph_for_new_metric(p_server_id bigint, OUT rc boolean) FROM public;

COMMENT ON FUNCTION public.create_graph_for_new_metric(p_server_id bigint, OUT rc boolean) IS
'Create default graphs for all new services.';

SELECT * FROM public.register_api('public.create_graph_for_new_metric(bigint)'::regprocedure);


-- This line must be the last one, so that every functions are owned
-- by the database owner
SELECT * FROM public.set_extension_owner('opm_core');
