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
