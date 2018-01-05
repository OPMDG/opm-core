-- This program is open source, licensed under the PostgreSQL License.
-- For license terms, see the LICENSE file.
--
-- Copyright (C) 2012-2018: Open PostgreSQL Monitoring Development Group

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION opm_core" to load this file. \quit


/*
 * public.register_api(regprocedure)
 * Add given function to the API function list
 * avaiable from application.
 */
CREATE OR REPLACE FUNCTION public.register_api(IN p_proc regprocedure,
    OUT proc regprocedure, OUT registered boolean)
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF
SET search_path TO public
AS $$
DECLARE
    v_ok boolean ;
BEGIN
    SELECT COUNT(*) = 0 INTO v_ok FROM public.api WHERE api.proc = p_proc;
    IF NOT v_ok THEN
        register_api.proc := p_proc ;
        register_api.registered := false ;
        RETURN ;
    END IF ;
    INSERT INTO public.api VALUES (p_proc)
    RETURNING p_proc, true
        INTO register_api.proc, register_api.registered;
END
$$;

REVOKE ALL ON FUNCTION public.register_api(regprocedure) FROM public;

COMMENT ON FUNCTION public.register_api(regprocedure) IS
'Add given function to the API function list avaiable from application.';

/*
public.update_user
Change the password of an opm user.

Can only be executed by superusers or own role.

@p_rolname: user to update
@p_password: new password
@return : true if everything went well
*/
CREATE OR REPLACE
FUNCTION public.update_user(IN p_rolname text, IN p_password text)
RETURNS boolean
LANGUAGE plpgsql VOLATILE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF NOT ( public.is_admin() OR p_rolname = public.session_role() ) THEN
        RAISE EXCEPTION 'You must be an admin.';
    END IF;

    IF public.is_account(p_rolname) THEN
        RAISE EXCEPTION 'Given role % is an account, not a user.', p_rolname;
    END IF;

    UPDATE public.roles
    SET password = md5(p_password||p_rolname)
    WHERE rolname = p_rolname;

    IF FOUND THEN
        RETURN true;
    END IF;

    RETURN false;
END
$$;

REVOKE ALL ON FUNCTION public.update_user(IN text, IN text) FROM public ;

COMMENT ON FUNCTION public.update_user(IN text, IN text) IS
'Change the password of an user.

Must be admin, or be the user updated.' ;

ALTER TABLE  public.metrics ADD tags text[] NOT NULL DEFAULT '{}';
ALTER TABLE  public.servers ADD tags text[] NOT NULL DEFAULT '{}';
ALTER TABLE  public.services ADD tags text[] NOT NULL DEFAULT '{}';

DELETE FROM public.api WHERE proc = 'list_servers()'::regprocedure ;
DROP FUNCTION public.list_servers() ;


CREATE OR REPLACE
FUNCTION public.list_servers()
RETURNS TABLE (id bigint, hostname text, id_role bigint, rolname text, tags text[])
LANGUAGE plpgsql STABLE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        RETURN QUERY SELECT s.id, s.hostname, s.id_role, r.rolname, s.tags
            FROM public.servers s
                LEFT JOIN public.roles r ON s.id_role = r.id;
    ELSE
        RETURN QUERY SELECT s.id, s.hostname, s.id_role, r.rolname, s.tags
            FROM public.servers s
                JOIN public.roles r ON s.id_role = r.id
            WHERE public.is_member(r.rolname);
    END IF;
END
$$;

REVOKE ALL ON FUNCTION public.list_servers() FROM public;

COMMENT ON FUNCTION public.list_servers() IS
'List servers available for the session user.';

SELECT * FROM public.register_api('public.list_servers()'::regprocedure) ;


DELETE FROM public.api WHERE proc= 'get_server(bigint)'::regprocedure ;
DROP FUNCTION public.get_server(bigint);

CREATE OR REPLACE
FUNCTION public.get_server(IN p_id bigint)
RETURNS TABLE (id bigint, hostname text, id_role bigint, rolname text, tags text[])
LANGUAGE plpgsql STABLE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        RETURN QUERY SELECT s.id, s.hostname, s.id_role, r.rolname, s.tags
            FROM public.servers s
            LEFT JOIN public.roles r ON s.id_role = r.id
            WHERE s.id = p_id;
    ELSE
        RETURN QUERY SELECT s.id, s.hostname, s.id_role, r.rolname, s.tags
        FROM public.servers s
            JOIN public.roles r ON s.id_role = r.id
        WHERE public.is_member(r.rolname)
            AND s.id = p_id;
    END IF;
END
$$;

REVOKE ALL ON FUNCTION public.get_server(bigint) FROM public;

COMMENT ON FUNCTION public.get_server(bigint) IS
'Returns all data about given server by id.';

SELECT * FROM public.register_api('public.get_server(bigint)'::regprocedure) ;


DELETE FROM public.api WHERE proc = 'list_services()'::regprocedure ;
DROP FUNCTION public.list_services() ;

CREATE OR REPLACE
FUNCTION public.list_services()
RETURNS TABLE (id bigint, id_server bigint, warehouse text,
               service text, last_modified date,
               creation_ts timestamp with time zone, servalid interval,
               tags text[])
LANGUAGE plpgsql STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
  RETURN QUERY SELECT ser.id, ser.id_server, ser.warehouse, ser.service,
          ser.last_modified, ser.creation_ts, ser.servalid, ser.tags
      FROM public.services ser JOIN public.list_servers() AS srv
        ON srv.id = ser.id_server;
END $$;

REVOKE ALL ON FUNCTION public.list_services() FROM public;

COMMENT ON FUNCTION public.list_services() IS
'List services available for the session user.';

SELECT * FROM public.register_api('public.list_services()'::regprocedure) ;


DELETE FROM public.api WHERE proc = 'list_graphs()'::regprocedure ;
DROP FUNCTION public.list_graphs() ;
CREATE OR REPLACE
FUNCTION public.list_graphs()
RETURNS TABLE (id bigint, graph text, description text, config json,
               id_server bigint, id_service bigint, warehouse text, tags text[])
LANGUAGE plpgsql STABLE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    -- FIXME DISTINCT ?!
    IF public.is_admin() THEN
        RETURN QUERY SELECT DISTINCT ON (g.id) g.id, g.graph,
                g.description, g.config,
                s3.id, s2.id, s2.warehouse,
                (s3.tags || s2.tags || m.tags)  as tags
            FROM public.graphs g
                LEFT JOIN public.series s1
                    ON g.id = s1.id_graph
                LEFT JOIN public.metrics m
                    ON s1.id_metric = m.id
                LEFT JOIN public.services s2
                    ON m.id_service = s2.id
                LEFT JOIN public.servers s3
                    ON s2.id_server = s3.id;
    ELSE
        RETURN QUERY SELECT DISTINCT ON (g.id) g.id, g.graph,
                g.description, g.config,
                s3.id, s2.id, s2.warehouse,
                (s3.tags || s2.tags || m.tags)  as tags
            FROM public.graphs g
                JOIN public.series s1
                    ON g.id = s1.id_graph
                JOIN public.metrics m
                    ON s1.id_metric = m.id
                JOIN public.services s2
                    ON m.id_service = s2.id
                JOIN public.servers s3
                    ON s2.id_server = s3.id
            WHERE public.is_member(s3.id_role);
    END IF;
END
$$;

REVOKE ALL ON FUNCTION public.list_graphs() FROM public ;

COMMENT ON FUNCTION public.list_graphs()
    IS 'List all visible graphs depending on the user rights';

SELECT * FROM public.register_api('public.list_graphs()'::regprocedure) ;


CREATE OR REPLACE
FUNCTION public.update_service_tags( p_id_service bigint, p_tags text[]) RETURNS VOID
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF SECURITY DEFINER
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'You must be an admin.';
  END IF;
  UPDATE public.services SET tags = p_tags WHERE id = p_id_service;
END
$$;

REVOKE ALL ON FUNCTION public.update_service_tags(bigint, text[]) FROM public;




COMMENT ON FUNCTION public.update_service_tags(bigint, text[]) IS
'Update the tags on a specific service. Admin role is required';

SELECT * FROM public.register_api('public.update_service_tags(bigint, text[])'::regprocedure);

DELETE FROM api WHERE proc = 'create_admin(text,text)'::regprocedure;
DROP FUNCTION public.create_admin (text,text);
/*
public.admin(IN p_admin name, IN p_passwd text)

Create a new admin.

Can only be executed by its owner (usually, the one of this database)

This should only be called when setting up OPM.

@return id: id of the new admin.
@return name: name of the new admin.
*/
CREATE OR REPLACE
FUNCTION public.create_admin (IN p_admin text, IN p_passwd text,
    OUT id bigint, OUT admname text)
LANGUAGE SQL STRICT VOLATILE LEAKPROOF
SET search_path TO public
AS $$
    WITH ins_admin AS (
        INSERT INTO public.roles (rolname, canlogin, password)
        VALUES (p_admin, 't'::boolean, pg_catalog.md5(p_passwd||p_admin))
        RETURNING roles.id, roles.rolname
    )
    INSERT INTO public.members
    SELECT ins_admin.rolname, 'opm_admins'::name
    FROM ins_admin;

    SELECT id, rolname
    FROM public.roles
    WHERE rolname = p_admin;
$$;


REVOKE ALL ON FUNCTION public.create_admin(IN p_admin text, IN p_passwd text, OUT bigint, OUT text)
    FROM public;

COMMENT ON FUNCTION public.create_admin(IN p_admin text, IN p_passwd text, OUT bigint, OUT text) IS
'public.admin(IN p_admin name, IN p_passwd text)

Create a new admin.

Can only be executed by its owner (usually, the one of this database)

This should only be called when setting up OPM.

@return id: id of the new admin.
@return name: name of the new admin.';

/*
public.delete_graph(bigint)
Delete a specific graph.
@id : unique identifier of graph to delete.
@return : true if everything went well

*/
CREATE OR REPLACE
FUNCTION public.delete_graph(IN p_id bigint,
    OUT deleted boolean)
LANGUAGE plpgsql VOLATILE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        DELETE FROM public.graphs
        WHERE graphs.id = p_id
        RETURNING true INTO deleted;
    ELSE
        DELETE FROM public.graphs
        USING public.list_graphs() AS g
        WHERE g.id = p_id AND graphs.id = g.id
        RETURNING true INTO deleted;
    END IF;

    IF deleted IS NULL THEN
        deleted := false;
    END IF;

    RETURN;
END
$$;

REVOKE ALL ON FUNCTION public.delete_graph(bigint) FROM public ;

COMMENT ON FUNCTION public.delete_graph(bigint)
    IS 'Delete given graph by id' ;

ALTER TABLE public.api ADD PRIMARY KEY (proc);

DELETE FROM api WHERE proc = 'list_metrics(bigint)'::regprocedure;
DROP FUNCTION public.list_metrics(bigint);
/*
public.list_metrics(bigint)

Return every metrics used in given graphs (by id) if current user is allowed to.
*/
CREATE OR REPLACE
FUNCTION public.list_metrics(p_id_graph bigint)
RETURNS TABLE (id_graph bigint, id_metric bigint, label text, unit text,
    id_service bigint, available boolean, tags text[])
LANGUAGE plpgsql STRICT STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        RETURN QUERY
            SELECT ss.id_graph, m.id, m.label, m.unit, m.id_service,
                s.id_graph IS NOT NULL AS available, m.tags
            FROM public.metrics AS ms
                JOIN public.series AS ss ON ms.id = ss.id_metric
                JOIN public.metrics AS m ON ms.id_service = m.id_service
                LEFT JOIN public.series s
                    ON (s.id_metric, s.id_graph) = (m.id, p_id_graph)
            WHERE ss.id_graph = p_id_graph
            GROUP BY 1,2,3,4,5,6;
    ELSE
        RETURN QUERY
            SELECT ss.id_graph, m.id, m.label, m.unit, m.id_service,
                s.id_graph IS NOT NULL AS available, m.tags
            FROM public.metrics AS ms
                JOIN public.series AS ss ON ms.id = ss.id_metric
                JOIN public.metrics AS m ON ms.id_service = m.id_service
                JOIN public.list_services() AS ser ON (ser.id = m.id_service)
                LEFT JOIN public.series s
                    ON (s.id_metric, s.id_graph) = (m.id, p_id_graph)
            WHERE ss.id_graph = p_id_graph
            GROUP BY 1,2,3,4,5,6;
    END IF;
END
$$;

REVOKE ALL ON FUNCTION public.list_metrics(bigint) FROM public;

COMMENT ON FUNCTION public.list_metrics(bigint) IS
'Return every metrics used in given graphs (by id) if current user is allowed to.';

SELECT * FROM public.register_api('public.list_metrics(bigint)'::regprocedure);

/*
is_member(rolname, accname)

A non admin user can only check if given rolname is member of one
of his own account.

@return rc: true if given rolname is member of accname
            NULL if one of given role is unknown
            false in other scenarios
*/
CREATE OR REPLACE
FUNCTION public.is_member(IN p_rolname text, IN p_accname text,
    OUT rc boolean)
LANGUAGE plpgsql STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF p_rolname IS NULL OR p_accname IS NULL THEN
        rc := FALSE;
        return ;
    END IF;
    IF public.is_admin() THEN
        SELECT pg_catalog.bool_or(m.member = p_accname) INTO rc
        FROM public.members AS m
        WHERE m.rolname = p_rolname;
    ELSE
        SELECT pg_catalog.bool_or(m.member = p_accname) INTO rc
        FROM public.members AS m
        WHERE m.rolname = p_rolname
            AND public.is_member(p_accname);
    END IF;

    IF rc IS NULL THEN
        rc := FALSE;
    END IF ;
    RETURN ;
END
$$;

REVOKE ALL ON FUNCTION public.is_member(IN p_rolname text, IN p_accname text, OUT rc boolean) FROM public;

COMMENT ON FUNCTION public.is_member(IN p_rolname text, IN p_accname text, OUT rc boolean) IS
'Tells if the given OPM role is member of given an OPM account.


A non admin user can only check if given rolname is member of one
of his own account.';

/*
is_member(accname)

Check if current session user is member of given account.

@return rc: true if current OPM session role is member of accname
*/
CREATE OR REPLACE
FUNCTION public.is_member(IN p_accname text, OUT rc boolean)
LANGUAGE SQL STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
    SELECT pg_catalog.count(1) = 1
    FROM public.members AS m
    WHERE m.rolname = public.session_role()
        AND m.member = p_accname;
$$;

REVOKE ALL ON FUNCTION public.is_member(IN p_accname text, OUT rc boolean) FROM public;

COMMENT ON FUNCTION public.is_member(IN p_accname text, OUT rc boolean) IS
'Tells if the current OPM session is member of given an OPM account.';

/*
is_member(id_account)

Check if current session user is member of given account (by id).

@return rc: true if current OPM session role is member of accname
*/
CREATE OR REPLACE
FUNCTION public.is_member(IN p_id_account bigint, OUT rc boolean)
LANGUAGE SQL STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
    SELECT pg_catalog.count(1) = 1
    FROM public.members AS m
        JOIN public.roles AS r ON (m.member = r.rolname)
    WHERE m.rolname = public.session_role()
        AND r.id = p_id_account;
$$;

REVOKE ALL ON FUNCTION public.is_member(IN p_id_account bigint, OUT rc boolean) FROM public;

COMMENT ON FUNCTION public.is_member(IN p_id_account bigint, OUT rc boolean) IS
'Tells if the current OPM session is member of given an OPM account by id.

A non admin user can only check if given rolname is member of one
of his own account.';

/*
public.list_graphs(id_server bigint)

Return every graphs user can see, including relations with
services and servers related informations for a specific server.
*/
CREATE OR REPLACE
FUNCTION public.list_graphs(p_id_server bigint)
RETURNS TABLE (id bigint, graph text, description text, config json,
               id_server bigint, id_service bigint, warehouse text, tags text[])
LANGUAGE plpgsql STABLE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    -- FIXME DISTINCT ?!
    IF public.is_admin() THEN
        RETURN QUERY SELECT DISTINCT ON (g.id) g.id, g.graph,
                g.description, g.config,
                s3.id, s2.id, s2.warehouse,
                (s3.tags || s2.tags || m.tags)  as tags
            FROM public.graphs g
                LEFT JOIN public.series s1
                    ON g.id = s1.id_graph
                LEFT JOIN public.metrics m
                    ON s1.id_metric = m.id
                LEFT JOIN public.services s2
                    ON m.id_service = s2.id
                LEFT JOIN public.servers s3
                    ON s2.id_server = s3.id
            WHERE s3.id = p_id_server ;
    ELSE
        RETURN QUERY SELECT DISTINCT ON (g.id) g.id, g.graph,
                g.description, g.config,
                s3.id, s2.id, s2.warehouse,
                (s3.tags || s2.tags || m.tags)  as tags
            FROM public.graphs g
                JOIN public.series s1
                    ON g.id = s1.id_graph
                JOIN public.metrics m
                    ON s1.id_metric = m.id
                JOIN public.services s2
                    ON m.id_service = s2.id
                JOIN public.servers s3
                    ON s2.id_server = s3.id
                    AND s3.id = p_id_server
            WHERE public.is_member(s3.id_role);
    END IF;
END
$$ ;

REVOKE ALL ON FUNCTION public.list_graphs(bigint) FROM public ;

COMMENT ON FUNCTION public.list_graphs(bigint)
    IS 'List all visible graphs depending on the user rights for a specific server.' ;

SELECT * FROM public.register_api('public.list_graphs(bigint)'::regprocedure) ;

/*
public.get_graph(id_graph bigint)

Return a specific graphs a user can see, including relations with
services and servers related informations.
*/
CREATE OR REPLACE
FUNCTION public.get_graph(p_id_graph bigint)
RETURNS TABLE (id bigint, graph text, description text, config json,
               id_server bigint, id_service bigint, warehouse text, tags text[])
LANGUAGE plpgsql STABLE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    -- FIXME DISTINCT ?!
    IF public.is_admin() THEN
        RETURN QUERY SELECT DISTINCT ON (g.id) g.id, g.graph,
                g.description, g.config,
                s3.id, s2.id, s2.warehouse,
                (s3.tags || s2.tags || m.tags)  as tags
            FROM public.graphs g
                LEFT JOIN public.series s1
                    ON g.id = s1.id_graph
                LEFT JOIN public.metrics m
                    ON s1.id_metric = m.id
                LEFT JOIN public.services s2
                    ON m.id_service = s2.id
                LEFT JOIN public.servers s3
                    ON s2.id_server = s3.id
            WHERE g.id = p_id_graph ;
    ELSE
        RETURN QUERY SELECT DISTINCT ON (g.id) g.id, g.graph,
                g.description, g.config,
                s3.id, s2.id, s2.warehouse,
                (s3.tags || s2.tags || m.tags)  as tags
            FROM public.graphs g
                JOIN public.series s1
                    ON g.id = s1.id_graph
                JOIN public.metrics m
                    ON s1.id_metric = m.id
                JOIN public.services s2
                    ON m.id_service = s2.id
                JOIN public.servers s3
                    ON s2.id_server = s3.id
            WHERE g.id = p_id_graph
                AND public.is_member(s3.id_role) ;
    END IF;
END
$$ ;

REVOKE ALL ON FUNCTION public.get_graph(bigint) FROM public ;

COMMENT ON FUNCTION public.get_graph(bigint)
    IS 'Get a specific visible graph depending on the user rights.' ;

SELECT * FROM public.register_api('public.get_graph(bigint)'::regprocedure) ;

/*
public.get_service(id)

Returns data about given service by id

@return id: Service id
@çeturn id_server: Id of associated server
@çeturn warehouse: name of the associated warehouse
@return service: Service name
@çeturn last_modified: last date service have been modified
@return creation_ts: creation timestamp of the service
@çeturn servalid: service interval retention
@return tag: Service tags
*/
CREATE OR REPLACE
FUNCTION public.get_service(IN p_id bigint)
RETURNS TABLE (id bigint, id_server bigint, warehouse text, service text, last_modified date, creation_ts timestamptz, tags text[])
LANGUAGE plpgsql STABLE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        RETURN QUERY SELECT s.id, s.id_server, s.warehouse, s.service, s.last_modified, s.creation_ts, s.tags
            FROM public.services s
            WHERE s.id = p_id;
    ELSE
        RETURN QUERY SELECT s.id, s.id_server, s.warehouse, s.service, s.last_modified, s.creation_ts, s.tags
        FROM public.services s
            JOIN public.servers s2 ON s2.id = s.id_server
            JOIN public.roles r ON s2.id_role = r.id
        WHERE public.is_member(r.rolname)
            AND s.id = p_id;
    END IF;
END
$$;

REVOKE ALL ON FUNCTION public.get_service(bigint) FROM public;

COMMENT ON FUNCTION public.get_service(bigint) IS
'Returns all data about given server by id.';

SELECT * FROM public.register_api('public.get_service(bigint)'::regprocedure);
