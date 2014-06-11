-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION opm_core" to load this file. \quit

-- This program is open source, licensed under the PostgreSQL License.
-- For license terms, see the LICENSE file.
--
-- Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

SET statement_timeout TO 0 ;

SET client_encoding = 'UTF8' ;
SET check_function_bodies = false ;

/* Make sure pr_grapher and pr_grapher_wh_nagios are installed, as there are a lot of structure changes */
DO
    $$
    DECLARE
        v_ok boolean;
    BEGIN
        SELECT COUNT(*) = 3 INTO v_ok FROM pg_extension WHERE extname IN ('pr_grapher','pr_grapher_wh_nagios','wh_nagios');
        IF (NOT v_ok) THEN
            RAISE EXCEPTION 'Upgrading opm-core from 1.1 to 2.0 need extensions pr_grapher and pr_grapher_wh_nagios installed';
        END IF;
    END;
    $$
LANGUAGE plpgsql ;

/*
Tables categories, graph_categories and nested_categories are not used anymore,
they will be deleted with the final DROP EXTENSION pr_grapher.
*/

/*
Handle graphs table :
  - change its extension from pr_grapher to opm-core
  - change its schema
  - change its sequence
  - remove columns y1_query and y2_query
  - change comment on column id to specify new schema
  - tell pg_dump to dump its content
*/
ALTER EXTENSION pr_grapher DROP TABLE pr_grapher.graphs ;
ALTER EXTENSION pr_grapher DROP SEQUENCE pr_grapher.graphs_id_seq ;
ALTER TABLE pr_grapher.graphs SET SCHEMA public ;
-- ALTER SEQUENCE pr_grapher.graphs_id_seq SET SCHEMA public ;
ALTER TABLE public.graphs ALTER COLUMN id SET DEFAULT nextval('public.graphs_id_seq') ;
ALTER TABLE public.graphs DROP COLUMN y1_query ;
ALTER TABLE public.graphs DROP COLUMN y2_query ;
COMMENT ON COLUMN public.graphs.id IS 'Graph unique identifier. Is the primary key of the table public.graphs.' ;
ALTER EXTENSION opm_core ADD TABLE public.graphs ;
ALTER EXTENSION opm_core ADD SEQUENCE public.graphs_id_seq ;
SELECT pg_catalog.pg_extension_config_dump('public.graphs', '') ;
SELECT pg_catalog.pg_extension_config_dump('public.graphs_id_seq', '') ;


/*
Handle wh_nagios.counters_detail :
  - change its extension from wh_nagios to opm-core
  - change its schema from wh_nagios to public
  - rename to metric_value
  - change its comment
*/

ALTER EXTENSION wh_nagios DROP TYPE wh_nagios.counters_detail ;
ALTER TYPE wh_nagios.counters_detail SET SCHEMA public ;
ALTER TYPE public.counters_detail RENAME TO metric_value ;
ALTER EXTENSION opm_core ADD TYPE public.metric_value ;
COMMENT ON TYPE public.metric_value IS 'Composite type to stored timestamped
values from metrics perfdata. Every warehouse has to return its data with this type' ;


/*
Handle wh_nagios.labels (renamed to wh_nagios.metrics) :
  - create public.metrics
  - handle the inheritance and all other modifications in wh_nagios upgrade script
    (including data importing)
  - tell pg_dump to dump its content
*/

CREATE TABLE public.metrics (
    id bigserial PRIMARY KEY,
    id_service bigint,
    label text,
    unit text
) ;
ALTER TABLE public.metrics OWNER TO opm; ;
REVOKE ALL ON TABLE public.metrics FROM public ;
COMMENT ON TABLE public.metrics IS 'Define a metric. This table has to be herited in warehouses.' ;
COMMENT ON COLUMN public.metrics.id IS 'Metric unique identifier.' ;
COMMENT ON COLUMN public.metrics.id_service IS 'References the warehouse.services unique identifier.' ;
COMMENT ON COLUMN public.metrics.label IS 'Metric title.' ;
COMMENT ON COLUMN public.metrics.unit IS 'Metric unit.' ;
SELECT pg_catalog.pg_extension_config_dump('public.metrics', '') ;
SELECT pg_catalog.pg_extension_config_dump('public.metrics_id_seq', '') ;


/*
Handle pr_grapher.graph_wh_nagios (renamed to series) :
  - create public.series
  - handle the inheritance and all other modifications in wh_nagios upgrade script
    (including data importing)
  - tell pg_dump to dump its content
*/

CREATE TABLE public.series (
    id_graph bigint,
    id_metric bigint,
    config json
) ;
ALTER TABLE public.series OWNER TO opm ;
REVOKE ALL ON TABLE public.series FROM public ;
COMMENT ON TABLE public.series IS 'Define a serie. This table has to be herited in warehouses.' ;
COMMENT ON COLUMN public.series.id_graph IS 'References graph unique identifier.' ;
COMMENT ON COLUMN public.series.id_metric IS 'References warehouse.metrics unique identifier.' ;
COMMENT ON COLUMN public.series.config IS 'Specific flotr2 configuration for this serie.' ;
SELECT pg_catalog.pg_extension_config_dump('public.series', '');


/*
Add functions which used to be in pr_grapher or pr_grapher_wh_nagios :
  - clone_graph(bigint)
  - create_graph_for_new_metric(bigint)
  - delete_graph(bigint)
  - get_sampled_metric_data(bigint,timestamp with time zone,timestamp with time zone,integer)
  - js_time(timestamp with time zone)
  - js_timetz(timestamp with time zone)
  - list_graphs()
  - list_metrics(bigint)
  - update_graph_metrics(bigint,bigint[])
*/

/* public.clone_graph(bigint)
Clone a graph, identified by its unique identifier.

@return: null if something went wrong, id of new graph otherwise.
*/
CREATE OR REPLACE FUNCTION public.clone_graph( p_id_graph bigint) RETURNS bigint
AS $$
DECLARE
    v_ok boolean;
    v_new_id bigint;
        v_state   TEXT;
        v_msg     TEXT;
        v_detail  TEXT;
        v_hint    TEXT;
        v_context TEXT;
BEGIN
    --IS user allowed to see graph ?
    SELECT COUNT(*) = 1 INTO v_ok
    FROM public.list_graphs()
    WHERE id = p_id_graph ;

    IF ( NOT v_ok ) THEN
        RETURN NULL ;
    END IF ;

    WITH graph AS (
        INSERT INTO public.graphs
            (graph, description, config)
        SELECT 'Clone - ' || graph,
          description, config
        FROM public.graphs
        WHERE id = p_id_graph RETURNING id
    ),
    ins AS (INSERT INTO public.series
        SELECT graph.id, id_metric
        FROM public.series, graph
        WHERE id_graph = p_id_graph
        RETURNING id_graph
    )
    SELECT DISTINCT id_graph INTO v_new_id
    FROM ins ;
    RETURN v_new_id ;
EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state   = RETURNED_SQLSTATE,
            v_msg     = MESSAGE_TEXT,
            v_detail  = PG_EXCEPTION_DETAIL,
            v_hint    = PG_EXCEPTION_HINT,
            v_context = PG_EXCEPTION_CONTEXT;
        raise WARNING 'Unable to clone graph : ''%'':
            state  : %
            message: %
            detail : %
            hint   : %
            context: %', p_id_graph, v_state, v_msg, v_detail, v_hint, v_context;
        RETURN NULL ;
END
$$
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER ;

ALTER FUNCTION public.clone_graph(bigint) OWNER TO opm ;
REVOKE ALL ON FUNCTION public.clone_graph(bigint) FROM public ;
GRANT EXECUTE ON FUNCTION public.clone_graph(bigint) TO opm_roles ;
COMMENT ON FUNCTION public.clone_graph(bigint) IS 'Clone a graph.' ;

/*
Function public.create_graph_for_new_metric(p_id_server bigint) returns boolean
@return rc: status

This function automatically generates all graphs for new metrics for a specified
server. If this function is called multiple times, it will only generate
"missing" graphs. A graph will be considered as missing if a metric is not
present in any graph. Therefore, it's currently impossible not to graph a metric.
FIXME: fix this limitation.
*/
CREATE OR REPLACE FUNCTION public.create_graph_for_new_metric(IN p_server_id bigint, OUT rc boolean)
AS $$
DECLARE
  v_state   TEXT;
  v_msg     TEXT;
  v_detail  TEXT;
  v_hint    TEXT;
  v_context TEXT;
  metricsrow record;
  v_nb bigint;
BEGIN
  --Does the server exists ?
  SELECT COUNT(*) INTO v_nb FROM public.servers WHERE id = p_server_id;
  IF (v_nb <> 1) THEN
    RAISE WARNING 'Server % does not exists.', p_server_id;
    rc := false;
    RETURN;
  END IF;

  --Is the user allowed to create graphs ?
  SELECT COUNT(*) INTO v_nb FROM public.list_servers() WHERE id = p_server_id;
  IF (v_nb <> 1) THEN
    RAISE WARNING 'User not allowed for server %.', p_server_id;
    rc := false;
    RETURN;
  END IF;

  FOR metricsrow IN (
    SELECT DISTINCT s.service, m.id_service, COALESCE(m.unit,'') AS unit
    FROM wh_nagios.services s
    JOIN wh_nagios.metrics m ON s.id = m.id_service
    WHERE s.id_server = p_server_id
        AND NOT EXISTS (
            SELECT 1 FROM public.series gs
            JOIN wh_nagios.metrics m2 ON m2.id=gs.id_metric
            WHERE m2.id=m.id
        )
    )
  LOOP
    WITH new_graphs (id_graph) AS (
      INSERT INTO public.graphs (graph, config)
        VALUES (metricsrow.service || ' (' || CASE WHEN metricsrow.unit = '' THEN 'no unit' ELSE 'in ' || metricsrow.unit END || ')', '{"type": "lines"}')
        RETURNING graphs.id
    )
    INSERT INTO public.series (id_graph, id_metric)
      SELECT new_graphs.id_graph, m.id
      FROM new_graphs
      CROSS JOIN public.metrics m
      WHERE m.id_service = metricsrow.id_service
        AND COALESCE(m.unit,'') = metricsrow.unit
        AND NOT EXISTS (
            SELECT 1 FROM public.series gs
            JOIN wh_nagios.metrics m2 ON m2.id=gs.id_metric
            WHERE m2.id=m.id
        );
  END LOOP;
  rc := true;
EXCEPTION
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_state   = RETURNED_SQLSTATE,
      v_msg     = MESSAGE_TEXT,
      v_detail  = PG_EXCEPTION_DETAIL,
      v_hint    = PG_EXCEPTION_HINT,
      v_context = PG_EXCEPTION_CONTEXT;
    raise notice E'Unhandled error on public.create_graph_for_new_metric:
      state  : %
      message: %
      detail : %
      hint   : %
      context: %', v_state, v_msg, v_detail, v_hint, v_context;
    rc := false;
END;
$$
LANGUAGE plpgsql
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.create_graph_for_new_metric(p_server_id bigint, OUT rc boolean) OWNER TO opm;
REVOKE ALL ON FUNCTION public.create_graph_for_new_metric(p_server_id bigint, OUT rc boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.create_graph_for_new_metric(p_server_id bigint, OUT rc boolean) TO opm_roles;

COMMENT ON FUNCTION public.create_graph_for_new_metric(p_server_id bigint, OUT rc boolean) IS 'Create default graphs for all new services.';

/* public.delete_graph(bigint)
Delete a specific graph.
@id : unique identifier of graph to delete.
@return : true if everything went well, false otherwise or if graph doesn't exists

*/
CREATE OR REPLACE FUNCTION public.delete_graph(p_id bigint)
RETURNS boolean
AS $$
DECLARE
    v_state      text ;
    v_msg        text ;
    v_detail     text ;
    v_hint       text ;
    v_context    text ;
    v_exists     boolean ;
BEGIN
    SELECT count(*) = 1 INTO v_exists FROM public.graphs WHERE id = p_id ;
    IF NOT v_exists THEN
        RETURN false ;
    END IF ;
    DELETE FROM public.graphs WHERE id = p_id ;
    RETURN true;
EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state   = RETURNED_SQLSTATE,
            v_msg     = MESSAGE_TEXT,
            v_detail  = PG_EXCEPTION_DETAIL,
            v_hint    = PG_EXCEPTION_HINT,
            v_context = PG_EXCEPTION_CONTEXT ;
        raise notice E'Unhandled error:
            state  : %
            message: %
            detail : %
            hint   : %
            context: %', v_state, v_msg, v_detail, v_hint, v_context ;
        RETURN false ;
END ;
$$
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.delete_graph(bigint) OWNER TO opm ;
REVOKE ALL ON FUNCTION public.delete_graph(bigint) FROM public ;
GRANT EXECUTE ON FUNCTION public.delete_graph(bigint) TO opm_admins ;

COMMENT ON FUNCTION public.delete_graph(bigint)
    IS 'Delete a graph' ;

/* public.get_sampled_metric_data(bigintn timestamptz, timestamptz, integer)
Sample a metric data to get the specified number of values.
@id : unique identifier of graph to delete.
@return : set of metric_value

*/
CREATE FUNCTION public.get_sampled_metric_data(p_id_metric bigint, p_timet_begin timestamp with time zone, p_timet_end timestamp with time zone, p_sample_num integer)
RETURNS TABLE(value metric_value)
AS $$
DECLARE
    v_warehouse name ;
    v_sec integer ;
BEGIN
    SELECT warehouse INTO v_warehouse FROM public.services s
        JOIN public.metrics m ON s.id = m.id_service
        WHERE m.id = p_id_metric ;
    IF (NOT FOUND) THEN
        RETURN;
    END IF ;

    IF (p_sample_num < 1) THEN
        RETURN ;
    END IF ;
    v_sec := ceil( ( extract(epoch FROM p_timet_end) - extract(epoch FROM p_timet_begin) ) / p_sample_num ) ;
    RETURN QUERY EXECUTE format('SELECT min(timet), max(value) FROM (SELECT * FROM %I.get_metric_data($1, $2, $3)) tmp GROUP BY (extract(epoch from timet)::float8/$4)::bigint*$4 ORDER BY 1', v_warehouse) USING p_id_metric, p_timet_begin, p_timet_end, v_sec ;
END;
$$
LANGUAGE plpgsql
STABLE
LEAKPROOF ;
ALTER FUNCTION public.get_sampled_metric_data(bigint, timestamp with time zone, timestamp with time zone, integer) OWNER TO opm;
REVOKE ALL ON FUNCTION public.get_sampled_metric_data(bigint, timestamp with time zone, timestamp with time zone, integer) FROM public;
GRANT EXECUTE ON FUNCTION public.get_sampled_metric_data(bigint, timestamp with time zone, timestamp with time zone, integer) TO opm_roles;
COMMENT ON FUNCTION public.get_sampled_metric_data(bigint, timestamp with time zone, timestamp with time zone, integer) IS
'Return sampled metric data for the specified metric with the specified number of samples.' ;

-- js_time: Convert the input date to ms (UTC), suitable for javascript
CREATE OR REPLACE FUNCTION public.js_time(timestamptz)
RETURNS bigint
AS $$
    SELECT (extract(epoch FROM $1)*1000)::bigint;
$$
LANGUAGE SQL
IMMUTABLE;

ALTER FUNCTION public.js_time(timestamptz) OWNER TO opm;
REVOKE ALL ON FUNCTION public.js_time(timestamptz) FROM public;
GRANT EXECUTE ON FUNCTION public.js_time(timestamptz) TO opm_roles;
COMMENT ON FUNCTION public.js_time(timestamptz) IS 'Return a timestamp without time zone formatted for javascript use.' ;

-- js_timetz: Convert the input date to ms (with timezone), suitable for javascript
CREATE OR REPLACE FUNCTION public.js_timetz(timestamptz)
RETURNS bigint
AS $$
    SELECT ((extract(epoch FROM $1) + extract(timezone FROM $1))*1000)::bigint;
$$
LANGUAGE SQL
IMMUTABLE;

ALTER FUNCTION public.js_timetz(timestamptz) OWNER TO opm;
REVOKE ALL ON FUNCTION public.js_timetz(timestamptz) FROM public;
GRANT EXECUTE ON FUNCTION public.js_timetz(timestamptz) TO opm_roles;
COMMENT ON FUNCTION public.js_timetz(timestamptz) IS 'Return a timestamp with time zone formatted for javascript use.' ;

/* public.list_graphs()
Return every graphs user can see, including relations with
services and servers related informations.

*/
CREATE OR REPLACE FUNCTION public.list_graphs() RETURNS TABLE
    (id bigint, graph text, description text, config json,
    id_server bigint, id_service bigint, warehouse name)
AS $$
DECLARE
BEGIN
    IF is_admin(session_user) THEN
        RETURN QUERY
            SELECT DISTINCT ON (g.id) g.id, g.graph,
                g.description, g.config,
                s3.id, s2.id, s2.warehouse
            FROM public.graphs g
            LEFT JOIN public.series s1
                ON g.id = s1.id_graph
            LEFT JOIN public.metrics m
                ON s1.id_metric = m.id
            LEFT JOIN public.services s2
                ON m.id_service = s2.id
            LEFT JOIN public.servers s3
                ON s2.id_server = s3.id ;
    ELSE
        RETURN QUERY
            SELECT DISTINCT ON (g.id) g.id, g.graph,
                g.description, g.config
                s3.id, s2.id, s2.warehouse
            FROM public.list_servers() s3
            JOIN public.list_services s2
                ON s3.id = s2.id_server
            JOIN public.metrics m
                ON s2.id = m.id_service
            JOIN public.series s1
                ON m.id_metric = m.id
            JOIN public.graphs g
                ON s1.id_graph = g.id ;

    END IF ;
END ;
$$
LANGUAGE plpgsql
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.list_graphs() OWNER TO opm ;
REVOKE ALL ON FUNCTION public.list_graphs() FROM public ;
GRANT EXECUTE ON FUNCTION public.list_graphs() TO opm_roles ;

COMMENT ON FUNCTION public.list_graphs()
    IS 'List all graphs' ;

/* public.list_metrics(bigint)
Return every metrics used in all graphs that current user is granted.
*/
CREATE OR REPLACE FUNCTION public.list_metrics(p_id_graph bigint)
RETURNS TABLE (id_graph bigint, id_metric bigint, label text, unit text,
    id_service bigint, available boolean )
AS $$
BEGIN

    IF is_admin(session_user) THEN
        RETURN QUERY
            SELECT ds.id_graph, m.id AS id_metric, m.label, m.unit,
                m.id_service, gs.id_graph IS NOT NULL AS available
            FROM public.metrics AS m
            JOIN (
                    SELECT DISTINCT m.id_service, gs.id_graph
                    FROM public.metrics AS m
                    JOIN public.series AS gs
                            ON m.id = gs.id_metric
                    WHERE gs.id_graph=p_id_graph
            ) AS ds
                    ON ds.id_service = m.id_service
            LEFT JOIN public.series gs
                    ON (gs.id_metric, gs.id_graph)=(m.id, ds.id_graph) ;
    ELSE
        RETURN QUERY
            SELECT ds.id_graph, m.id AS id_metric, m.label, m.unit,
                m.id_service, gs.id_graph IS NOT NULL AS available
            FROM wh_nagios.metrics AS m
            JOIN (
                    SELECT DISTINCT m.id_service, gs.id_graph
                    FROM wh_nagios.metrics AS m
                    JOIN public.series AS gs
                            ON m.id = gs.id_metric
                    WHERE gs.id_graph=p_id_graph
                        AND EXISTS (SELECT 1
                            FROM public.list_services() ls
                            WHERE m.id_service=ls.id
                        )
            ) AS ds
                    ON ds.id_service = m.id_service
            LEFT JOIN public.series gs
                    ON (gs.id_metric, gs.id_graph)=(m.id, ds.id_graph);
    END IF;
END;
$$
LANGUAGE plpgsql
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.list_metrics(bigint) OWNER TO opm;
REVOKE ALL ON FUNCTION public.list_metrics(bigint) FROM public;
GRANT EXECUTE ON FUNCTION public.list_metrics(bigint) TO opm_roles;

COMMENT ON FUNCTION public.list_metrics(bigint)
    IS 'List metrics used in a specific graph.';

/* public.update_graph_metrics(bigint, bigint[])
Update what are the metrics associated to the given graph.

Returns 2 arrays:
  * added bigint[]: Array of added metrics
  * removed bigint[]: Array of removed metrics
*/
CREATE OR REPLACE FUNCTION public.update_graph_metrics( p_id_graph bigint, p_id_metrics bigint[], OUT added bigint[], OUT removed bigint[])
AS $$
DECLARE
    v_result record;
    v_remove  bigint[];
    v_add     bigint[];
BEGIN
    IF NOT is_admin(session_user) THEN
        SELECT 1 FROM public.list_graphs()
        WHERE id = p_id_graph;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Graph id % does not exists or not granted.', p_id_graph;
        END IF;
    END IF;

    FOR v_result IN
        SELECT gs.id_metric AS to_remove, a.id_metric AS to_add
        FROM (
            SELECT id_metric FROM public.series
            WHERE id_graph = p_id_graph
        ) AS gs
        FULL JOIN (
            SELECT * FROM unnest ( p_id_metrics )
        ) AS a(id_metric) ON a.id_metric = gs.id_metric
        WHERE gs.id_metric IS NULL OR a.id_metric IS NULL
    LOOP
        /* if "existing" is NULL, the metric should be added to the graph
         * else "given" is NULL, the metric should be removed from the
         * graph
         */
        IF v_result.to_add IS NOT NULL THEN
            v_add := array_append(v_add, v_result.to_add);
        ELSE
            v_remove := array_append(v_remove, v_result.to_remove);
        END IF;
    END LOOP;

    -- Add new metrics to the graph
    INSERT INTO public.series (id_graph, id_metric)
    SELECT p_id_graph, unnest(v_add);

    -- Remove metrics from the graph
    PERFORM 1 FROM public.graphs
    WHERE id = p_id_graph FOR UPDATE;

    FOR v_result IN SELECT array_agg(id_metric) AS vals, to_delete
        FROM (
                SELECT id_metric, count(*) > 1 AS to_delete
                FROM public.series
                WHERE id_metric = any( v_remove ) group by id_metric
        ) AS sub
        GROUP BY to_delete
    LOOP
        IF v_result.to_delete THEN
            DELETE FROM public.series
            WHERE id_metric = any( v_result.vals )
                AND id_graph = p_id_graph;
        ELSE
            UPDATE public.series SET id_graph = NULL
            WHERE id_metric = any( v_result.vals )
                AND id_graph = p_id_graph;
        END IF;
    END LOOP;

    added := v_add; removed := v_remove;
END
$$
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER;

ALTER FUNCTION public.update_graph_metrics(bigint, bigint[]) OWNER TO opm ;
REVOKE ALL ON FUNCTION public.update_graph_metrics(bigint, bigint[]) FROM public ;
GRANT EXECUTE ON FUNCTION public.update_graph_metrics(bigint, bigint[]) TO opm_roles ;
COMMENT ON FUNCTION public.update_graph_metrics(bigint, bigint[]) IS 'Update what are the metrics associated to the given graph.' ;


/*
Finally, drop extensions pr_grapher and pr_grapher_wh_nagios
*/
-- DROP EXTENSION pr_grapher;
-- DROP EXTENSION pr_grapher_wh_nagios;
