-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION wh_nagios" to load this file. \quit

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;
SET search_path = public, pg_catalog;

/*
\c postgres
DROP DATABASE IF EXISTS opm;
DROP ROLE IF EXISTS opm;
DROP ROLE IF EXISTS opm_admins;
DROP ROLE IF EXISTS opm_roles;
*/

CREATE ROLE opm CREATEROLE;
CREATE ROLE opm_admins CREATEROLE;
CREATE ROLE opm_roles;
GRANT opm TO opm_admins;
GRANT opm_roles TO opm_admins;

DO LANGUAGE plpgsql
$$
DECLARE
    v_dbname name;
BEGIN
    SELECT current_database() INTO v_dbname;
    EXECUTE format('REVOKE ALL ON DATABASE %I FROM public',v_dbname);
    EXECUTE format('GRANT ALL ON DATABASE %I TO opm',v_dbname);
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO opm_roles',v_dbname);
END;
$$;

/*
CREATE DATABASE opm OWNER opm;
\c opm
*/

-- Map properties and info between accounts/users and internal pgsql roles
CREATE TABLE public.roles (
    id bigserial PRIMARY KEY,
    rolname name NOT NULL,
    creation_ts timestamp with time zone DEFAULT now() NOT NULL,
    rolconfig text[]
);
CREATE UNIQUE INDEX idx_roles_rolname
    ON roles USING btree (rolname);
ALTER TABLE public.roles OWNER TO opm;
REVOKE ALL ON TABLE public.roles FROM public ;

COMMENT ON TABLE public.roles IS 'Map properties and info between accounts/users and internal pgsql roles';

COMMENT ON COLUMN public.roles.id IS 'Role uniquer identier. Is the primary key of table roles';
COMMENT ON COLUMN public.roles.rolname IS 'rolname, same as rolname from table pg_roles';
COMMENT ON COLUMN public.roles.creation_ts IS 'Role creation date and time';
COMMENT ON COLUMN public.roles.rolconfig IS 'Specific configuration for a particular role';


INSERT INTO public.roles (rolname) VALUES ('opm_admins');

CREATE TABLE public.servers (
    id bigserial PRIMARY KEY,
    hostname name NOT NULL,
    id_role bigint REFERENCES public.roles (id)
);

CREATE UNIQUE INDEX idx_servers_hostname
    ON public.servers USING btree(hostname) ;
ALTER TABLE public.servers OWNER TO opm ;

REVOKE ALL ON TABLE public.servers FROM public ;

COMMENT ON COLUMN public.servers.id IS 'Server unique identifier. Is the primary key' ;
COMMENT ON COLUMN public.servers.hostname IS 'hostname of the server, as referenced by dispatcher. Must be unique' ;
COMMENT ON COLUMN public.servers.id_role IS 'owner of the server' ;
COMMENT ON TABLE public.servers IS 'Table servers lists all referenced servers' ;

CREATE TABLE public.services (
    id bigserial PRIMARY KEY,
    id_server bigint NOT NULL REFERENCES public.servers (id),
    warehouse name NOT NULL,
    service text NOT NULL,
    last_modified date DEFAULT (now())::date NOT NULL,
    creation_ts timestamp with time zone DEFAULT now() NOT NULL,
    last_cleanup timestamp with time zone DEFAULT now() NOT NULL,
    servalid interval
);
CREATE UNIQUE INDEX idx_services_service
    ON services USING btree (service);
ALTER TABLE public.services OWNER TO opm;
REVOKE ALL ON TABLE public.services FROM public ;

COMMENT ON TABLE public.services IS 'Table services lists all available metrics.

This table is a master table. Each warehouse have a specific services tables inherited from this master table';

COMMENT ON COLUMN public.services.id IS 'Service unique identifier. Is the primary key';
COMMENT ON COLUMN public.services.id_server IS 'Identifier of the server';
COMMENT ON COLUMN public.services.warehouse IS 'warehouse that stores this specific metric';
COMMENT ON COLUMN public.services.service IS 'service name that provides a specific metric';
COMMENT ON COLUMN public.services.last_modified IS 'last day that the dispatcher pushed datas in the warehouse';
COMMENT ON COLUMN public.services.creation_ts IS 'warehouse creation date and time for this particular service';
COMMENT ON COLUMN public.services.servalid IS 'data retention time';

SELECT pg_catalog.pg_extension_config_dump('public.roles', '');
SELECT pg_catalog.pg_extension_config_dump('public.roles_id_seq', '');
SELECT pg_catalog.pg_extension_config_dump('public.servers', '');
SELECT pg_catalog.pg_extension_config_dump('public.servers_id_seq', '');
SELECT pg_catalog.pg_extension_config_dump('public.services', '');
SELECT pg_catalog.pg_extension_config_dump('public.services_id_seq', '');

/* public.create_account
Create a new account.

It creates a role (NOLOGIN) and register it in the public.accounts table.

TODO: grant the account to opm_admins and opm ?

Can only be executed by roles opm and opm_admins.

@return id: id of the new account.
@return name: name of the new account.
*/
CREATE OR REPLACE FUNCTION
public.create_account (IN p_account text,
                       OUT id bigint, OUT accname text)
AS $$
DECLARE
    v_err integer;
BEGIN
    EXECUTE format('SELECT COUNT(*) FROM pg_roles WHERE rolname = %L', p_account) INTO STRICT v_err;

    IF (v_err != 0) THEN
        RAISE EXCEPTION 'Given role already exists: %', p_account;
        RETURN;
    END IF;
    EXECUTE format('CREATE ROLE %I', p_account);
    EXECUTE format('GRANT opm_roles TO %I', p_account);
    EXECUTE format('GRANT %I TO opm_admins WITH ADMIN OPTION', p_account);
    INSERT INTO public.roles (rolname) VALUES (p_account)
        RETURNING roles.id, roles.rolname
            INTO create_account.id, create_account.accname;
END
$$
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.create_account(IN text, OUT bigint, OUT text)
    OWNER TO opm;
REVOKE ALL ON FUNCTION public.create_account(IN text, OUT bigint, OUT text)
    FROM public;
GRANT ALL ON FUNCTION public.create_account(IN text, OUT bigint, OUT text)
    TO opm_admins;

COMMENT ON FUNCTION public.create_account (IN text, OUT bigint, OUT text) IS 'Create a new account.

It creates a role (NOLOGIN) and register it in the public.roles table.

TODO: grant the account to opm_admins and opm ?

Can only be executed by roles opm and opm_admins.

@return id: id of the new account.
@return name: name of the new account.';

/* public.create_user
Create a new user for an account.

It creates a role (LOGIN, ENCRYPTED PASSWORD) and register it in the
public.roles table.

The p_accounts MUST have at least one account. We don't want user with no
accounts.

Can only be executed by roles opm and opm_admins.

@return id: id of the new account.
@return name: name of the new account.
*/
CREATE OR REPLACE FUNCTION
public.create_user (IN p_user text, IN p_passwd text, IN p_accounts name[],
                    OUT id bigint, OUT usename text)
AS $$
DECLARE
    p_account name;
    v_err integer;
BEGIN
    EXECUTE format('SELECT COUNT(*) FROM pg_roles WHERE rolname = %L', p_user) INTO STRICT v_err;

    IF (v_err != 0) THEN
        RAISE EXCEPTION 'Given user already exists: %', p_user;
        RETURN;
    END IF;

    IF coalesce(array_length(p_accounts, 1), 0) < 1 THEN
        -- or maybe we should raise an exception ?
        RAISE WARNING 'A user must have at least one associated account!';
        RETURN;
    END IF;

    EXECUTE format('CREATE ROLE %I LOGIN ENCRYPTED PASSWORD %L',
        p_user, p_passwd);

    INSERT INTO public.roles (rolname) VALUES (p_user) RETURNING roles.id, roles.rolname
        INTO create_user.id, create_user.usename;

    EXECUTE format('GRANT opm_roles TO %I', p_user);

    v_err := 0;
    FOREACH p_account IN ARRAY p_accounts
    LOOP
        IF (is_account(p_account)) THEN
            v_err := v_err + 1;
            PERFORM public.grant_account(p_user, p_account);
        END IF;
    END LOOP;

    IF (v_err = 0) THEN
        -- or maybe we should raise an exception ?
        RAISE WARNING 'A user must have at least one associated account!';
    END IF;
END
$$
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.create_user(IN text, IN text, IN name[], OUT boolean)
    OWNER TO opm;
REVOKE ALL ON FUNCTION public.create_user(IN text, IN text, IN name[], OUT boolean)
    FROM public;
GRANT ALL ON FUNCTION public.create_user(IN text, IN text, IN name[], OUT boolean)
    TO opm_admins;

COMMENT ON FUNCTION public.create_user (IN p_user text, IN p_passwd text, IN p_accounts name[],
                    OUT rc boolean) IS 'Create a new user for an account.

It creates a role (LOGIN, ENCRYPTED PASSWORD) and register it in the
public.roles table.

The p_accounts MUST have at least one account. We don''t want user with no
accounts.

Can only be executed by roles opm and opm_admins.

@return id: id of the new account.
@return name: name of the new account.';

/*public.drop_account

Drop an account.

Also drop all roles that are connected only to this particular account.

@return id: oid of the dropped roles
@return rolname: name of the dropped roles
*/
CREATE OR REPLACE FUNCTION
public.drop_account(IN p_account name)
 RETURNS TABLE(id bigint, rolname name)
AS $$
-- It drops an account and also roles that are only in this account.
DECLARE
        p_role record;
BEGIN

    IF p_account = 'opm_admins' THEN
      RAISE EXCEPTION 'Account "opm_admins" can not be deleted!';
    END IF;

    IF (is_account(p_account) = false) THEN
      RAISE EXCEPTION 'Account % is not a opm account!', p_account;
    END IF;

    /* get list of roles to drop with the account.
     * don't drop roles that are part of several accounts
     */
    FOR rolname IN EXECUTE
        'SELECT t.rolname FROM (
            SELECT u.rolname, count(*)
            FROM pg_roles AS u
                JOIN pg_auth_members AS am ON (am.member = u.oid)
                JOIN pg_catalog.pg_roles AS a ON (a.oid = am.roleid)
            WHERE pg_has_role(u.oid, $1, ''MEMBER'')
                AND u.rolname NOT IN (''postgres'', $2)
                AND a.rolname <> ''opm_roles''
            GROUP BY 1
        ) AS t
        WHERE t.count = 1' USING p_account, p_account
    LOOP
        EXECUTE format('SELECT * FROM drop_user(%L)', rolname) INTO drop_account.id, drop_account.rolname;
        RETURN NEXT;
    END LOOP;

    EXECUTE 'DELETE FROM public.roles WHERE rolname = $1 RETURNING id, rolname'
        INTO drop_account.id, drop_account.rolname USING p_account;
    EXECUTE format('DROP ROLE %I', p_account);

    RETURN NEXT;

    RETURN;
END;
$$
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.drop_account (IN name)
    OWNER TO opm;
REVOKE ALL ON FUNCTION public.drop_account (IN name)
    FROM public;
GRANT ALL ON FUNCTION public.drop_account (IN name)
    TO opm_admins;

COMMENT ON FUNCTION public.drop_account(IN name) IS 'Drop an account.

It drops an account and also roles that are only in this account.';

/*public.drop_user

Drop an user.

@return rc: return id and name of the dropped user.
*/
CREATE OR REPLACE FUNCTION
public.drop_user(IN p_user name, OUT id bigint, OUT rolname name)
AS $$
DECLARE
        p_rolname name;
BEGIN
    IF (is_user(p_user) = false) THEN
        /* or do we raise an exception ? */
        RETURN;
    END IF;

    EXECUTE 'SELECT rolname FROM public.roles WHERE rolname = $1'
        INTO STRICT p_rolname USING p_user;

    EXECUTE 'DELETE FROM public.roles
            WHERE rolname = $1
            RETURNING roles.id, roles.rolname'
        INTO drop_user.id, drop_user.rolname USING p_user;

    EXECUTE format('DROP ROLE %I', p_user);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE NOTICE 'Non-existent user %', p_user;
    WHEN OTHERS THEN
        RAISE LOG 'Impossible to drop user: %', p_user;
END;
$$
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.drop_user (IN name)
    OWNER TO opm;
REVOKE ALL ON FUNCTION public.drop_user (IN name)
    FROM public;
GRANT ALL ON FUNCTION public.drop_user (IN name)
    TO opm_admins;

COMMENT ON FUNCTION public.drop_user(IN name) IS 'Drop a user.';

/* public.list_users
*/
CREATE OR REPLACE FUNCTION public.list_users(p_account name DEFAULT NULL)
    RETURNS TABLE (useid bigint, accname name, rolname name)
AS $$
DECLARE
    query text := $q$
        WITH all_roles (id,rolname) AS (
            SELECT u.id, u.rolname
            FROM roles u
            JOIN pg_roles r ON u.rolname = r.rolname
            WHERE rolcanlogin
        ), assigned AS (
            SELECT u.id, a.rolname as accname, u.rolname
            FROM public.roles AS u
                JOIN pg_catalog.pg_roles AS r ON (u.rolname = r.rolname)
                JOIN pg_auth_members AS m ON (r.oid = m.member)
                JOIN pg_roles AS a ON (a.oid = m.roleid)
            WHERE a.rolname <> r.rolname
                AND a.rolname <> 'opm_roles'
                AND r.rolcanlogin
        )
        SELECT ar.id, a.accname, ar.rolname
        FROM all_roles ar
            LEFT JOIN assigned a ON ar.rolname = a.rolname
        WHERE TRUE
    $q$;
BEGIN
    IF p_account IS NOT NULL THEN
        query := format(
            query || ' AND a.accname = %L',
            p_account
        );
    END IF;

    IF NOT pg_has_role(session_user, 'opm_admins', 'MEMBER') THEN
        query := query || $q$ AND pg_has_role(session_user, a.accname, 'MEMBER')$q$;
    END IF;

    RETURN QUERY EXECUTE query;
END
$$
LANGUAGE plpgsql
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.list_users(name) OWNER TO opm;
REVOKE ALL ON FUNCTION public.list_users(name) FROM public;
GRANT ALL ON FUNCTION public.list_users(name) TO public;

COMMENT ON FUNCTION public.list_users(name) IS 'List users.

If current user is member of opm_admins, list all users and account on the system.

If current user is not admin, list all users and account who are related to the current user.';

/* public.list_accounts
*/
CREATE OR REPLACE FUNCTION public.list_accounts()
    RETURNS TABLE (accid bigint, accname name)
AS $$
DECLARE
    query text := $q$
        SELECT a.id, r.rolname
        FROM public.roles AS a
            JOIN pg_catalog.pg_roles AS r ON (a.rolname = r.rolname)
        WHERE NOT r.rolcanlogin
    $q$;
BEGIN
    IF NOT pg_has_role(session_user, 'opm_admins', 'MEMBER') THEN
        query := query || $q$ AND pg_has_role(session_user, r.rolname, 'MEMBER')$q$;
    END IF;

    RETURN QUERY EXECUTE query;
END
$$
LANGUAGE plpgsql
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.list_accounts() OWNER TO opm;
REVOKE ALL ON FUNCTION public.list_accounts() FROM public;
GRANT EXECUTE ON FUNCTION public.list_accounts() TO public;

COMMENT ON FUNCTION public.list_accounts() IS 'List accounts.

If current user is member of opm_admins, list all account on the system.

If current user is not admin, list all account who are related to the current user.';

/*
is_user(rolname)

@return rc: true if the given rolname is a simple user
 */
CREATE OR REPLACE FUNCTION public.is_user(IN p_rolname name, OUT rc boolean)
AS $$
    SELECT count(*) > 0
    FROM public.list_users()
    WHERE rolname = p_rolname;
$$
LANGUAGE SQL
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.is_user(IN name, OUT boolean) OWNER TO opm;
REVOKE ALL ON FUNCTION public.is_user(IN name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.is_user(IN name, OUT boolean) TO public;

COMMENT ON FUNCTION public.is_user(IN name, OUT boolean) IS 'Tells if the given rolname is a user.';

/*
is_account(rolname)

@return rc: true if the given rolname is an account
            NULL if role does not exist

 */
CREATE OR REPLACE FUNCTION public.is_account(IN p_rolname name, OUT rc boolean)
AS $$
    SELECT count(*) > 0
    FROM public.list_accounts()
    WHERE accname = p_rolname;
$$
LANGUAGE SQL
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.is_account(IN name, OUT boolean) OWNER TO opm;
REVOKE ALL ON FUNCTION public.is_account(IN name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.is_account(IN name, OUT boolean) TO public;

COMMENT ON FUNCTION public.is_account(IN name, OUT boolean) IS 'Tells if the given rolname is an account.';

/*
is_admin(rolname)

@return rc: true if the given rolname is an admin
            NULL if role does not exist

 */
CREATE OR REPLACE FUNCTION public.is_admin(IN p_rolname name, OUT rc boolean)
AS $$
    BEGIN
        SELECT CASE pg_has_role(p_rolname,'opm_admins','MEMBER')
            WHEN true THEN true
            WHEN false THEN false
        END INTO rc;
    EXCEPTION
        WHEN OTHERS THEN
            rc := NULL;
    END;
$$
LANGUAGE plpgsql
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.is_admin(IN name, OUT boolean) OWNER TO opm;
REVOKE ALL ON FUNCTION public.is_admin(IN name, OUT boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.is_admin(IN name, OUT boolean) TO public;

COMMENT ON FUNCTION public.is_admin(IN name, OUT boolean) IS 'Tells if the given rolname is an admin.';

/*
is_opm_role(rolname)

@return: if given role exists as an OPM role (account or user), returns its
oid, id, name and canlogin attributes. NULL if not exists or not a OPM
role.
 */
CREATE OR REPLACE FUNCTION public.is_opm_role(IN p_rolname name, OUT boolean)
AS $$
    SELECT bool_or(x)
    FROM (
        SELECT public.is_user($1)
        UNION ALL
        SELECT public.is_account($1)
    ) t(x);
$$
LANGUAGE SQL
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.is_opm_role(IN name, OUT oid, OUT bigint, OUT name, OUT boolean) OWNER TO opm;
REVOKE ALL ON FUNCTION public.is_opm_role(IN name, OUT oid, OUT bigint, OUT name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.is_opm_role(IN name, OUT oid, OUT bigint, OUT name, OUT boolean) TO public;

COMMENT ON FUNCTION public.is_opm_role(IN name, OUT oid, OUT bigint, OUT name, OUT boolean) IS
'If given role exists as a OPM role (account or user), returns true';

/*
wh_exists(wh)

@return rc: true if the given warehouse exists
 */
CREATE OR REPLACE FUNCTION public.wh_exists(IN p_whname name, OUT rc boolean)
AS $$
    SELECT count(*) > 0
    FROM public.list_warehouses()
    WHERE whname = $1;
$$
LANGUAGE SQL
STABLE
LEAKPROOF;

ALTER FUNCTION public.wh_exists(IN name, OUT boolean) OWNER TO opm;
REVOKE ALL ON FUNCTION public.wh_exists(IN name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.wh_exists(IN name, OUT boolean) TO public;

COMMENT ON FUNCTION public.wh_exists(IN name, OUT boolean) IS 'Returns true if the given warehouse exists.';

/*
pr_exists(wh)

@return rc: true if the given process exists
 */
CREATE OR REPLACE FUNCTION public.pr_exists(IN p_prname name, OUT rc boolean)
AS $$
    SELECT count(*) > 0
    FROM public.list_processes()
    WHERE prname = $1;
$$
LANGUAGE SQL
STABLE
LEAKPROOF;

ALTER FUNCTION public.pr_exists(IN name, OUT boolean) OWNER TO opm;
REVOKE ALL ON FUNCTION public.pr_exists(IN name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.pr_exists(IN name, OUT boolean) TO public;

COMMENT ON FUNCTION public.pr_exists(IN name, OUT boolean) IS 'Returns true if the given process exists.';

/*
public.grant_dispatcher(wh, role)

@return rc: state of the operation
 */
CREATE OR REPLACE FUNCTION public.grant_dispatcher(IN p_whname name, IN p_rolname name, OUT rc boolean)
AS $$
DECLARE
        v_state   TEXT;
        v_msg     TEXT;
        v_detail  TEXT;
        v_hint    TEXT;
        v_context TEXT;
BEGIN
    rc := wh_exists(p_whname);

    IF NOT rc THEN
        RAISE WARNING 'Warehouse ''%'' does not exists!', p_whname;
        RETURN;
    END IF;

    -- FIXME check success before return
    EXECUTE format('SELECT %I.grant_dispatcher($1)', p_whname)
        INTO STRICT rc USING p_rolname;

    IF NOT rc THEN
        RAISE WARNING 'FAILED';
    ELSE
        RAISE NOTICE 'GRANTED';
    END IF;

    RETURN;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state   = RETURNED_SQLSTATE,
            v_msg     = MESSAGE_TEXT,
            v_detail  = PG_EXCEPTION_DETAIL,
            v_hint    = PG_EXCEPTION_HINT,
            v_context = PG_EXCEPTION_CONTEXT;
        raise WARNING 'Could not grant dispatch to ''%'' on ''%'':
            state  : %
            message: %
            detail : %
            hint   : %
            context: %', p_rolname, p_whname, v_state, v_msg, v_detail, v_hint, v_context;
        rc := false;
END;
$$
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.grant_dispatcher(IN name, IN name, OUT boolean) OWNER TO opm;
REVOKE ALL ON FUNCTION public.grant_dispatcher(IN name, IN name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.grant_dispatcher(IN name, IN name, OUT boolean) TO opm_admins;

COMMENT ON FUNCTION public.grant_dispatcher(IN name, IN name, OUT boolean)
IS 'Grant a role to dispatch performance data in a warehouse hub table.';

/*
public.revoke_dispatcher(wh, role)

@return rc: state of the operation
 */
CREATE OR REPLACE FUNCTION public.revoke_dispatcher(IN p_whname name, IN p_rolname name, OUT rc boolean)
AS $$
DECLARE
        v_state   TEXT;
        v_msg     TEXT;
        v_detail  TEXT;
        v_hint    TEXT;
        v_context TEXT;
BEGIN

    /* verify that the given warehouse exists */
    rc := wh_exists(p_whname);

    IF NOT rc THEN
        RAISE WARNING 'Warehouse ''%'' does not exists!', p_whname;
        RETURN;
    END IF;

    -- FIXME check success before return
    EXECUTE format('SELECT %I.revoke_dispatcher($1)', p_whname)
        INTO STRICT rc USING p_rolname;

    IF NOT rc THEN
        RAISE WARNING 'FAILED';
    ELSE
        RAISE NOTICE 'REVOKED';
    END IF;

    RETURN;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE NOTICE 'Non-existent user %', p_rolname;
        rc := false;
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state   = RETURNED_SQLSTATE,
            v_msg     = MESSAGE_TEXT,
            v_detail  = PG_EXCEPTION_DETAIL,
            v_hint    = PG_EXCEPTION_HINT,
            v_context = PG_EXCEPTION_CONTEXT;
        raise notice E'Unhandled error: impossible to grant user % on hub % :
            state  : %
            message: %
            detail : %
            hint   : %
            context: %', p_rolname, p_whname, v_state, v_msg, v_detail, v_hint, v_context;
        rc := false;
END;
$$
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.revoke_dispatcher(IN name, IN name, OUT boolean) OWNER TO opm;
REVOKE ALL ON FUNCTION public.revoke_dispatcher(IN name, IN name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.revoke_dispatcher(IN name, IN name, OUT boolean) TO opm_admins;

COMMENT ON FUNCTION public.revoke_dispatcher(IN name, IN name, OUT boolean) IS 'Revoke dispatch ability for a give role on a given hub table.';

/*
grant_server()
 */
CREATE OR REPLACE FUNCTION public.grant_server(IN p_server_id bigint, IN p_rolname name, OUT rc boolean)
AS $$
DECLARE
    v_state   TEXT;
    v_msg     TEXT;
    v_detail  TEXT;
    v_hint    TEXT;
    v_context TEXT;
    v_serversrow public.servers%rowtype;
    v_servicesrow public.services%rowtype;
    v_rolid bigint;
    v_nb integer;
BEGIN
    rc := false;
    --Does the server exists ?
    SELECT COUNT(*) INTO v_nb FROM public.servers WHERE id = p_server_id;
    IF (v_nb <> 1) THEN
        RAISE WARNING 'Server % does not exists.', p_server_id;
        RETURN;
    END IF;

    --Does the role exists ?
    IF (NOT is_opm_role(p_rolname)) THEN
        RAISE WARNING 'Role % is not an OPM role.', p_rolname;
        RETURN;
    END IF;

    --Is the server already owned ?
    EXECUTE format('SELECT * FROM public.servers WHERE id = %s', p_server_id) INTO v_serversrow;
    IF (v_serversrow.id_role IS NOT NULL) THEN
        RAISE WARNING 'The server % is already owned by an opm role %', v_serversrow.hostname, v_serversrow.id_role;
        RETURN;
    END IF;

    rc := true; -- must be set to true, if no partitions
    EXECUTE format('SELECT id FROM public.roles WHERE rolname = %L', p_rolname) INTO v_rolid;
    EXECUTE format('UPDATE public.servers SET id_role = %s WHERE id = %s', v_rolid, p_server_id);
    FOR v_servicesrow IN SELECT * FROM public.list_services()
    LOOP
        /* put the ACL on the partitions, let the warehouse function do it */
        EXECUTE format('SELECT %I.grant_service(%s, %L)', v_servicesrow.warehouse, v_servicesrow.id, p_rolname) INTO STRICT rc;
        IF (NOT rc) THEN
            RAISE EXCEPTION 'Could not perform grant_service on warehouse %', v_servicesrow.warehouse;
        END IF;
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state   = RETURNED_SQLSTATE,
            v_msg     = MESSAGE_TEXT,
            v_detail  = PG_EXCEPTION_DETAIL,
            v_hint    = PG_EXCEPTION_HINT,
            v_context = PG_EXCEPTION_CONTEXT;
        RAISE WARNING E'Unhandled error: impossible to grant server % for user % :
            state  : %
            message: %
            detail : %
            hint   : %
            context: %', p_server_id, p_rolname, v_state, v_msg, v_detail, v_hint, v_context;
        rc := false;
END;
$$
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.grant_server(IN p_server_id bigint, IN p_rolname name, OUT rc boolean) OWNER TO opm;
REVOKE ALL ON FUNCTION public.grant_server(IN p_server_id bigint, IN p_rolname name, OUT rc boolean) FROM public;
GRANT ALL ON FUNCTION public.grant_server(IN p_server_id bigint, IN p_rolname name, OUT rc boolean) TO opm_admins;

COMMENT ON FUNCTION public.grant_server(IN p_server_id bigint, IN p_rolname name, OUT rc boolean) IS 'Grant SELECT on a server.';


/*
revoke_server()
 */
CREATE OR REPLACE FUNCTION public.revoke_server(IN p_server_id bigint, IN p_rolname name, OUT rc boolean)
AS $$
DECLARE
    v_state   TEXT;
    v_msg     TEXT;
    v_detail  TEXT;
    v_hint    TEXT;
    v_context TEXT;
    v_servicesrow public.services%rowtype;
    v_rolid bigint;
    v_nb integer;
BEGIN
    rc := false;
    --Does the server exists ?
    SELECT COUNT(*) INTO v_nb FROM public.servers WHERE id = p_server_id;
    IF (v_nb <> 1) THEN
        RAISE WARNING 'Server % does not exists.', p_server_id;
        RETURN;
    END IF;

    --Does the role own the server ?
    EXECUTE format('SELECT COUNT(*) FROM public.servers s JOIN public.roles r ON s.id_role = r.id WHERE s.id = %s AND r.rolname = %L', p_server_id, p_rolname) INTO v_nb;
    IF (v_nb <> 1) THEN
        RAISE WARNING 'The server % is not owned by an OPM role %', p_server_id, p_rolname;
        RETURN;
    END IF;

    rc := true; -- must be set to true, if no partitions
    EXECUTE format('UPDATE public.servers SET id_role = NULL WHERE id = %s', p_server_id);
    FOR v_servicesrow IN SELECT * FROM public.list_services()
    LOOP
        /* revoke the ACL on the partitions, let the warehouse function do it */
        EXECUTE format('SELECT %I.revoke_service(%s, %L)', v_servicesrow.warehouse, v_servicesrow.id, p_rolname) INTO STRICT rc;
        IF (NOT rc) THEN
            RAISE EXCEPTION 'Could not perform revoke_service on warehouse %', v_servicesrow.warehouse;
        END IF;
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state   = RETURNED_SQLSTATE,
            v_msg     = MESSAGE_TEXT,
            v_detail  = PG_EXCEPTION_DETAIL,
            v_hint    = PG_EXCEPTION_HINT,
            v_context = PG_EXCEPTION_CONTEXT;
        RAISE WARNING E'Unhandled error: impossible to revoke server % from user % :
            state  : %
            message: %
            detail : %
            hint   : %
            context: %', p_server_id, p_rolname, v_state, v_msg, v_detail, v_hint, v_context;
        rc := false;
END;
$$
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.revoke_server(IN p_server_id bigint, IN p_rolname name, OUT rc boolean) OWNER TO opm;
REVOKE ALL ON FUNCTION public.revoke_server(IN p_server_id bigint, IN p_rolname name, OUT rc boolean) FROM public;
GRANT ALL ON FUNCTION public.revoke_server(IN p_server_id bigint, IN p_rolname name, OUT rc boolean) TO opm_admins;

COMMENT ON FUNCTION public.revoke_server(IN p_server_id bigint, IN p_rolname name, OUT rc boolean) IS 'Revoke SELECT from a server.';

/*
list_servers()
 */
CREATE OR REPLACE FUNCTION public.list_servers()
  RETURNS TABLE (id bigint, hostname name, rolname name)
AS $$
BEGIN
    IF pg_has_role(session_user, 'opm_admins', 'MEMBER') THEN
        RETURN QUERY SELECT s.id, s.hostname, r.rolname
            FROM public.servers s
            LEFT JOIN public.roles r ON s.id_role = r.id;
    ELSE
        RETURN QUERY SELECT s.id, s.hostname, r.rolname
            FROM public.servers s
            JOIN public.roles r ON s.id_role = r.id
            WHERE pg_has_role(session_user, r.rolname, 'MEMBER') ;
    END IF;
END;
$$ LANGUAGE plpgsql
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.list_servers() OWNER TO opm;
REVOKE ALL ON FUNCTION public.list_servers() FROM public;
GRANT EXECUTE ON FUNCTION public.list_servers() TO public;

COMMENT ON FUNCTION public.list_servers() IS 'List servers available for the session user.';

/*
list_services()
 */
CREATE OR REPLACE FUNCTION public.list_services()
    RETURNS TABLE (id bigint, id_server bigint, warehouse name, service text, last_modified date, creation_ts timestamp with time zone, servalid interval)
AS $$
BEGIN
    RETURN QUERY SELECT s.id, s.id_server, s.warehouse, s.service,
            s.last_modified, s.creation_ts, s.servalid
            FROM (SELECT * FROM public.list_servers() ) ls
            JOIN public.services s ON ls.id = s.id_server;

END;
$$ LANGUAGE plpgsql
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.list_services() OWNER TO opm;
REVOKE ALL ON FUNCTION public.list_services() FROM public;
GRANT EXECUTE ON FUNCTION public.list_services() TO public;

COMMENT ON FUNCTION public.list_services() IS 'List services available for the session user.';

/*
grant_account(p_rolname name, p_accountname name)

@return : true if granted
            NULL if role or account does not exist

 */
CREATE OR REPLACE FUNCTION public.grant_account(p_rolname name, p_accountname name) RETURNS boolean
AS $$
DECLARE
    v_grantoption text;
BEGIN
    -- we use pg_has_role instead of is_user because it can be the first account added
    -- we have to catch exception in case role does not exists
    BEGIN
        IF ( (NOT pg_has_role(p_rolname, 'opm_roles', 'MEMBER')) OR (NOT is_account(p_accountname)) ) THEN
            RETURN NULL;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN NULL;
    END;

    v_grantoption = '';
    IF ( (is_admin(session_user)) OR (pg_has_role(session_user, p_accountname, 'MEMBER')) )THEN
        IF (p_accountname = 'opm_admins') THEN
            -- Allow members of opm_admins to add new admins
            v_grantoption = ' WITH ADMIN OPTION';
        END IF;
        EXECUTE format('GRANT %I TO %I %s', p_accountname, p_rolname, v_grantoption);
        RETURN true;
    ELSE
        RETURN false;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Could not grant account % to user %', p_accountname, p_rolname;
        RETURN false;
END;
$$ LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.grant_account(p_rolname name, p_accountname name) OWNER TO opm;
REVOKE ALL ON FUNCTION public.grant_account(p_rolname name, p_accountname name) FROM public;
GRANT EXECUTE ON FUNCTION public.grant_account(p_rolname name, p_accountname name) TO public;

COMMENT ON FUNCTION public.grant_account(p_rolname name, p_accountname name) IS 'Grant an account to a user.';


/*
revoke_account(p_rolname name, p_accountname name)

@return : true if revoked
            NULL if role or account does not exist

 */
CREATE OR REPLACE FUNCTION public.revoke_account(p_rolname name, p_accountname name) RETURNS boolean
AS $$
DECLARE
    v_ok boolean;
BEGIN
    IF ( (NOT is_user(p_rolname)) OR (NOT is_account(p_accountname)) ) THEN
        RETURN NULL;
    END IF;
    IF (NOT pg_has_role(p_rolname, p_accountname, 'MEMBER')) THEN
        RETURN false;
    END IF;

    SELECT (COUNT(*) > 0) INTO v_ok FROM public.list_users() WHERE rolname = p_rolname AND accname != p_accountname;
    IF (NOT v_ok) THEN
        RAISE NOTICE 'Could not revoke account % from user % : only existing account for this user', p_accountname, p_rolname;
        RETURN false;
    END IF;

    IF ( (is_admin(session_user)) OR (pg_has_role(session_user, p_accountname, 'MEMBER')) )THEN
        EXECUTE format('REVOKE %I FROM %I', p_accountname, p_rolname);
        RETURN true;
    ELSE
        RETURN false;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Could not revoke account % from user %', p_accountname, p_rolname;
        RETURN false;
END;
$$ LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.revoke_account(p_rolname name, p_accountname name) OWNER TO opm;
REVOKE ALL ON FUNCTION public.revoke_account(p_rolname name, p_accountname name) FROM public;
GRANT EXECUTE ON FUNCTION public.revoke_account(p_rolname name, p_accountname name) TO public;

COMMENT ON FUNCTION public.revoke_account(p_rolname name, p_accountname name) IS 'Revoke an account from a user.';

/*
list_warehouses()

@return whname: names of the warehouses
 */
CREATE OR REPLACE FUNCTION public.list_warehouses() RETURNS TABLE (whname name)
AS $$
BEGIN
    RETURN QUERY SELECT n.nspname
        FROM pg_namespace n
        JOIN pg_available_extensions e ON n.nspname = e.name AND e.installed_version IS NOT NULL
        WHERE nspname ~ '^wh_';
END;
$$ LANGUAGE plpgsql
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.list_warehouses() OWNER TO opm;
REVOKE ALL ON FUNCTION public.list_warehouses() FROM public;
GRANT EXECUTE ON FUNCTION public.list_warehouses() TO public;

COMMENT ON FUNCTION public.list_warehouses() IS 'List all warehouses';

/*
list_processes()

@return prname: names of the processes
 */
CREATE OR REPLACE FUNCTION public.list_processes() RETURNS TABLE (prname name)
AS $$
BEGIN
    RETURN QUERY SELECT n.nspname
        FROM pg_namespace n
        JOIN pg_available_extensions e ON n.nspname = e.name AND e.installed_version IS NOT NULL
        WHERE n.nspname ~ '^pr_';
END;
$$ LANGUAGE plpgsql
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.list_processes() OWNER TO opm;
REVOKE ALL ON FUNCTION public.list_processes() FROM public;
GRANT EXECUTE ON FUNCTION public.list_processes() TO public;

COMMENT ON FUNCTION public.list_processes() IS 'List all processes';
