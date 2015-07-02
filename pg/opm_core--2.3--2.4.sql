-- This program is open source, licensed under the PostgreSQL License.
-- For license terms, see the LICENSE file.
--
-- Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION opm_core" to load this file. \quit

----------------------------------------------
-- Graphs configuration templates
CREATE TABLE public.graphs_templates (
    id bigserial        PRIMARY KEY,
    service_pattern     text NOT NULL,
    unit                text,
    config              json NOT NULL,
    metric_pattern      text
) ;

REVOKE ALL ON TABLE public.graphs_templates FROM public ;

COMMENT ON TABLE  public.graphs_templates                 IS 'Store configuration templates for new graphs';
COMMENT ON COLUMN public.graphs_templates.id              IS 'Unique identifier of a configuration template.' ;
COMMENT ON COLUMN public.graphs_templates.service_pattern IS 'Regex pattern to match a service for a new graph.' ;
COMMENT ON COLUMN public.graphs_templates.unit            IS 'Unit to match a service for a new graph.' ;
COMMENT ON COLUMN public.graphs_templates.config          IS 'Configuration to apply to the new graph.' ;
COMMENT ON COLUMN public.graphs_templates.metric_pattern  IS 'Regex pattern to match a serie to remove from a new graph. It needs to also match the service pattern.' ;

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
  v_owner     bigint ;
  metricsrow  record ;
  graphsrow   record ;
  templaterow record ;
  seriesrow   record ;
  v_graph_id  bigint ;
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
    AND COALESCE(m.unit, '') = '';

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
                )
                RETURNING id_graph',
        metricsrow.service, metricsrow.unit, metricsrow.warehouse, metricsrow.id_service)
        INTO v_graph_id ;

        IF (graphsrow.nb = 0) THEN
            -- First graph to be created, let's check if a template
            -- configuration exists.
            -- if multiple templates matches the service name, well you did
            -- something wrong, so only apply the first created
            FOR templaterow IN (
                SELECT service_pattern, config, metric_pattern
                FROM public.graphs_templates
                WHERE  COALESCE(unit, '') = metricsrow.unit
                AND metricsrow.service ~* service_pattern
                ORDER BY id
                LIMIT 1
            )
            LOOP
                UPDATE public.graphs SET config = templaterow.config
                WHERE id = v_graph_id ;
                -- Now, check for series to remove
                IF (templaterow.metric_pattern IS NOT NULL) THEN
                    UPDATE public.series s
                    SET id_graph = NULL
                    FROM public.metrics m
                    WHERE m.label ~* templaterow.metric_pattern
                    AND id_graph = v_graph_id
                    AND id_metric = m.id ;
                END IF ;
            END LOOP ;
        END IF ;
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
    END IF ;
  END LOOP ;
  rc := true ;
END
$$;

REVOKE ALL ON FUNCTION public.create_graph_for_new_metric(p_server_id bigint, OUT rc boolean) FROM public;

COMMENT ON FUNCTION public.create_graph_for_new_metric(p_server_id bigint, OUT rc boolean) IS
'Create default graphs for all new services.';

SELECT * FROM public.register_api('public.create_graph_for_new_metric(bigint)'::regprocedure);

/*
public.list_graphs_templates(id)

List the graphs templates. If an id is provided, only return this one.

@p_id : id of the graph template to list (optional)
*/
CREATE OR REPLACE
FUNCTION public.list_graphs_templates(IN p_id bigint)
RETURNS TABLE(id bigint, service_pattern text, unit text, config text, metric_pattern text)
LANGUAGE plpgsql VOLATILE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_where text ;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'You must be an admin.' ;
    END IF;

    IF (p_id IS NULL) THEN
        v_where := 'true';
    ELSE
        v_where = 'id = ' || p_id;
    END IF ;
    RETURN QUERY EXECUTE format(
        'SELECT id, service_pattern, unit, config::text, metric_pattern
        FROM public.graphs_templates
        WHERE %s', v_where);
END
$$;

REVOKE ALL ON FUNCTION public.list_graphs_templates(IN bigint)
    FROM public;

COMMENT ON FUNCTION public.list_graphs_templates(IN bigint) IS
'List the graphs templates. You must be an admin to call this function.';

SELECT * FROM public.register_api('public.list_graphs_templates(bigint)'::regprocedure);
/*
public.delete_graph_template(id)

Drop a graph template. Only admin can do this.

@p_id : id of the graph template to drop
@return rc: return true if succeeded.
*/
CREATE OR REPLACE
FUNCTION public.delete_graph_template(IN p_id bigint, OUT rc boolean)
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_id bigint;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'You must be an admin.';
    END IF;

    DELETE FROM public.graphs_templates AS r
    WHERE id = p_id
    RETURNING id INTO v_id ;

    rc := (v_id IS NOT NULL) ;
END
$$;

REVOKE ALL ON FUNCTION public.delete_graph_template(IN bigint)
    FROM public;

COMMENT ON FUNCTION public.delete_graph_template(IN bigint) IS
'Drop a graph template. You must be an admin to call this function.';

SELECT * FROM public.register_api('public.delete_graph_template(bigint)'::regprocedure);

/*
public.create_graph_template(text, text)

Create a graph template. Only admin can do this.

@service_pattern: The service regex for a new graph template
@return id: id of the new graph template
*/
CREATE OR REPLACE
FUNCTION public.create_graph_template(IN p_service_pattern text,
    IN p_unit text, OUT p_id bigint)
LANGUAGE plpgsql VOLATILE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'You must be an admin.';
    END IF;

    IF p_service_pattern IS NULL THEN
        RAISE EXCEPTION 'You must provide a service pattern.';
    END IF;

    INSERT INTO public.graphs_templates (service_pattern, unit, config)
    VALUES (p_service_pattern, p_unit, '{}')
    RETURNING id INTO p_id ;
END
$$;

REVOKE ALL ON FUNCTION public.create_graph_template(IN text, IN text)
    FROM public;

COMMENT ON FUNCTION public.create_graph_template(IN text, IN text) IS
'Create a graph template. You must be an admin to call this function.';

SELECT * FROM public.register_api('public.create_graph_template(text, text)'::regprocedure);

/*
public.update_graph_template(bigint, text, text, json, text)

Create a graph template. Only admin can do this.

@id: id of the graph template to update
@service_pattern: service regex for a new graph template
@config: json
@metric_pattern: the metric regex for metric to delete from a new graph
@return rc: true if everything went well
*/
CREATE OR REPLACE
FUNCTION public.update_graph_template(IN p_id bigint, IN p_service_pattern text,
    IN p_unit text, IN p_config json, IN p_metric_pattern text, OUT rc boolean)
LANGUAGE plpgsql VOLATILE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_id bigint;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'You must be an admin.' ;
    END IF ;

    rc := false ;

    IF (COALESCE(p_service_pattern,'') = ''  OR p_config IS NULL) THEN
        return ;
    END IF ;
    UPDATE public.graphs_templates
    SET service_pattern = p_service_pattern,
        unit = p_unit,
        config = p_config,
        metric_pattern = p_metric_pattern
    WHERE id = p_id
    RETURNING id INTO v_id ;

    rc := (v_id IS NOT NULL) ;
END
$$;

REVOKE ALL ON FUNCTION public.update_graph_template(IN bigint, IN text, IN text, IN json, IN text)
    FROM public;

COMMENT ON FUNCTION public.update_graph_template(IN bigint, IN text, IN text, IN json, IN text) IS
'Update a graph template. You must be an admin to call this function.';

SELECT * FROM public.register_api('public.update_graph_template(bigint, text, text, json, text)'::regprocedure);



-- This line must be the last one, so that every functions are owned
-- by the database owner
SELECT * FROM public.set_extension_owner('opm_core');
