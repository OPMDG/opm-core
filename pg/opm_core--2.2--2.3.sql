-- This program is open source, licensed under the PostgreSQL License.
-- For license terms, see the LICENSE file.
--
-- Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION opm_core" to load this file. \quit


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

DROP FUNCTION public.list_servers();

CREATE OR REPLACE
FUNCTION public.list_servers()
RETURNS TABLE (id bigint, hostname text, rolname text, tags text[])
LANGUAGE plpgsql STABLE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        RETURN QUERY SELECT s.id, s.hostname, r.rolname, s.tags
            FROM public.servers s
                LEFT JOIN public.roles r ON s.id_role = r.id;
    ELSE
        RETURN QUERY SELECT s.id, s.hostname, r.rolname, s.tags
            FROM public.servers s
                JOIN public.roles r ON s.id_role = r.id
            WHERE public.is_member(r.rolname);
    END IF;
END
$$;

REVOKE ALL ON FUNCTION public.list_servers() FROM public;

COMMENT ON FUNCTION public.list_servers() IS
'List servers available for the session user.';

SELECT * FROM public.register_api('public.list_servers()'::regprocedure);


DROP FUNCTION public.list_services();

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

SELECT * FROM public.register_api('public.list_services()'::regprocedure);


DROP FUNCTION public.list_graphs();
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

SELECT * FROM public.register_api('public.list_graphs()'::regprocedure);


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

/*
 * public.register_api(name, name)
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
