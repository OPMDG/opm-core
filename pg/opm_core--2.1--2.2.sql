-- This program is open source, licensed under the PostgreSQL License.
-- For license terms, see the LICENSE file.
--
-- Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION opm_core" to load this file. \quit

-- Configure pg_dump for table "members"
SELECT pg_catalog.pg_extension_config_dump('public.members', '');


/* v2.1

public.clone_graph(bigint)

Clone given graph by id.

@return: id of the new graph.
*/
CREATE OR REPLACE
FUNCTION public.clone_graph(p_id_graph bigint)
RETURNS bigint
LANGUAGE plpgsql VOLATILE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_new_id  bigint;
    v_whname  text;
BEGIN
    -- IS user allowed to see graph ?
    PERFORM 1
    FROM public.list_graphs() as g
    WHERE g.id = p_id_graph ;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Graph not found or not allowed.';
    END IF;

    -- Which warehouse ?
    SELECT warehouse INTO v_whname
    FROM public.list_graphs()
    WHERE id = p_id_graph ;

    EXECUTE format('
        WITH ins_graph AS (
            INSERT INTO public.graphs (graph, description, config)
            SELECT ''Clone - '' || g.graph, g.description, g.config
            FROM public.graphs AS g
            WHERE g.id = %s
            RETURNING graphs.id
        ),
        ins_ser AS (
            INSERT INTO %I.series
            SELECT ng.id, s.id_metric
            FROM public.series AS s, ins_graph AS ng
            WHERE s.id_graph = %1$s
            RETURNING series.id_graph
        )
        SELECT ns.id_graph
        FROM ins_ser AS ns
        LIMIT 1',
    p_id_graph, v_whname) INTO v_new_id;

    RETURN v_new_id;
END
$$;

REVOKE ALL ON FUNCTION public.clone_graph(bigint) FROM public;

COMMENT ON FUNCTION public.clone_graph(bigint) IS 'Clone given graph by id.

@return: id of the new graph.';


/* v2.1
public.list_users(p_accname)

Return the id, role name and account of all users in given account if OPM session role is admin.
If the user is not admin, returns the list of users from the same account

@return useid:   the user id
@return accname: the account name
@return rolname: the user name
*/
CREATE OR REPLACE
FUNCTION public.list_users(IN p_accname text)
RETURNS TABLE (useid bigint, accname text, rolname text)
LANGUAGE plpgsql STRICT STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        RETURN QUERY SELECT r.id, m.member, r.rolname
            FROM public.roles AS r
                JOIN public.members AS m ON (r.rolname=m.rolname)
            WHERE r.canlogin
                AND m.member = p_accname;
    ELSE
        RETURN QUERY SELECT r.id, m.member, r.rolname
            FROM public.roles AS r
                JOIN public.members AS m ON (r.rolname=m.rolname)
            WHERE r.canlogin
                AND m.member = p_accname
                AND public.is_member(m.member);
    END IF;
END
$$;

REVOKE ALL ON FUNCTION public.list_users(text) FROM public;

COMMENT ON FUNCTION public.list_users(text) IS 'List OPM users.

If current user is admin, list all users from the given account.

If current user is not admin, list all users from given account if the user is member of this account.';


/* v2.1
public.drop_user(name)

Drop an user. Only admin can do this.
User can not commit suicide.

@return rc: return id and name of the dropped user.
*/
CREATE OR REPLACE
FUNCTION public.drop_user(IN p_user text, OUT id bigint, OUT rolname text)
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'You must be an admin.';
    END IF;

    DELETE FROM public.roles AS r
    WHERE r.rolname = p_user
        AND p_user <> public.session_role()
    RETURNING r.id, r.rolname
        INTO drop_user.id, drop_user.rolname;
END
$$;

REVOKE ALL ON FUNCTION public.drop_user(IN text)
    FROM public;

COMMENT ON FUNCTION public.drop_user(IN text) IS
'Drop an existing OPM user. You must be an admin to call this function.';


/* v2.1
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

    RETURN;
END
$$;

REVOKE ALL ON FUNCTION public.delete_graph(bigint) FROM public ;

COMMENT ON FUNCTION public.delete_graph(bigint)
    IS 'Delete given graph by id' ;
