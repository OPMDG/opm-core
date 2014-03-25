-- This program is open source, licensed under the PostgreSQL License.
-- For license terms, see the LICENSE file.
--
-- Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION opm_core" to load this file. \quit

/***************************************
*
* Make sure query won't get cancelled
* and handle default ACL
*
***************************************/

SET client_encoding = 'UTF8';
SET check_function_bodies = false;

CREATE ROLE opm CREATEROLE;
CREATE ROLE opm_admins CREATEROLE;
CREATE ROLE opm_roles;

-- default privileges
ALTER SCHEMA public OWNER TO opm;

GRANT opm TO opm_admins;
GRANT opm_roles TO opm_admins;
REVOKE ALL ON SCHEMA public FROM public;
GRANT USAGE ON SCHEMA public TO opm_roles;

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

/***************************************
*
* Create extension's objects
*
***************************************/

CREATE TYPE public.metric_value AS (
    timet timestamp with time zone,
    value numeric
) ;
ALTER TYPE public.metric_value OWNER TO opm ;
COMMENT ON TYPE public.metric_value IS 'Composite type to stored timestamped
values from metrics perdata. Every warehouse has to return its data with this type' ;

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

COMMENT ON TABLE public.roles IS 'Map properties and info between accounts/users and internal pgsql roles.' ;

COMMENT ON COLUMN public.roles.id IS 'Role uniquer identier. Is the primary key of table roles.' ;
COMMENT ON COLUMN public.roles.rolname IS 'Rolname, same as rolname from table pg_roles.' ;
COMMENT ON COLUMN public.roles.creation_ts IS 'Role creation date and time.';
COMMENT ON COLUMN public.roles.rolconfig IS 'Specific configuration for a particular role.' ;


INSERT INTO public.roles (rolname) VALUES ('opm_admins');

CREATE TABLE public.servers (
    id bigserial PRIMARY KEY,
    hostname name NOT NULL,
    id_role bigint REFERENCES public.roles (id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE UNIQUE INDEX idx_servers_hostname
    ON public.servers USING btree(hostname) ;
ALTER TABLE public.servers OWNER TO opm ;

REVOKE ALL ON TABLE public.servers FROM public ;

COMMENT ON COLUMN public.servers.id IS 'Server unique identifier. Is the primary key.' ;
COMMENT ON COLUMN public.servers.hostname IS 'Hostname of the server, as referenced by dispatcher. Must be unique.' ;
COMMENT ON COLUMN public.servers.id_role IS 'Owner of the server.' ;
COMMENT ON TABLE public.servers IS 'Table servers lists all referenced servers.' ;

CREATE TABLE public.services (
    id bigserial PRIMARY KEY,
    id_server bigint NOT NULL REFERENCES public.servers (id) ON UPDATE CASCADE ON DELETE CASCADE,
    warehouse name NOT NULL,
    service text NOT NULL,
    last_modified date DEFAULT (now())::date NOT NULL,
    creation_ts timestamp with time zone DEFAULT now() NOT NULL,
    last_cleanup timestamp with time zone DEFAULT now() NOT NULL,
    servalid interval,
    oldest_record timestamp with time zone,
    newest_record timestamp with time zone
);
CREATE UNIQUE INDEX idx_services_service
    ON services USING btree (id_server,service);
ALTER TABLE public.services OWNER TO opm;
REVOKE ALL ON TABLE public.services FROM public ;

COMMENT ON TABLE public.services IS 'Table services lists all available metrics.

This table is a master table. Each warehouse have a specific services tables inherited from this master table.';

COMMENT ON COLUMN public.services.id IS 'Service unique identifier. Is the primary key.';
COMMENT ON COLUMN public.services.id_server IS 'Identifier of the server.';
COMMENT ON COLUMN public.services.warehouse IS 'Warehouse that stores this specific metric.';
COMMENT ON COLUMN public.services.service IS 'Service name that provides a specific metric.';
COMMENT ON COLUMN public.services.last_modified IS 'Last day that the dispatcher pushed datas in the warehouse.';
COMMENT ON COLUMN public.services.creation_ts IS 'Warehouse creation date and time for this particular service.';
COMMENT ON COLUMN public.services.last_cleanup IS 'Last launch of "warehouse".cleanup_service(). Each warehouse has to implement his own, if needed.';
COMMENT ON COLUMN public.services.servalid IS 'Data retention time.';
COMMENT ON COLUMN public.services.oldest_record IS 'Timestamp of the oldest value stored for the service.' ;
COMMENT ON COLUMN public.services.newest_record IS 'Timestamp of the newest value stored for the service.' ;

CREATE TABLE public.graphs (
  id bigserial PRIMARY KEY,
  graph text NOT NULL,
  description text,
  config json
) ;
ALTER TABLE public.graphs OWNER TO opm ;
REVOKE ALL ON TABLE public.graphs FROM public ;
COMMENT ON TABLE public.graphs IS 'Store all graphs definitions.' ;
COMMENT ON COLUMN public.graphs.id IS 'Graph unique identifier. Is the primary key of the table public.graphs.' ;
COMMENT ON COLUMN public.graphs.graph IS 'Title of the graph.' ;
COMMENT ON COLUMN public.graphs.description IS 'Description of the graph.' ;
COMMENT ON COLUMN public.graphs.config IS 'Specific flotr2 graph configuration, stored in json.' ;

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

CREATE TABLE public.metrics (
    id bigserial PRIMARY KEY,
    id_service bigint,
    label text,
    unit text
); ;
ALTER TABLE public.metrics OWNER TO opm; ;
REVOKE ALL ON TABLE public.metrics FROM public ;
COMMENT ON TABLE public.metrics IS 'Define a metric. This table has to be herited in warehouses.' ;
COMMENT ON COLUMN public.metrics.id IS 'Metric unique identifier.' ;
COMMENT ON COLUMN public.metrics.id_service IS 'References the warehouse.services unique identifier..' ;
COMMENT ON COLUMN public.metrics.label IS 'Metric title.' ;
COMMENT ON COLUMN public.metrics.unit IS 'Metric unit.' ;

/***************************************
*
* Tell pg_dump which objects to dump
*
***************************************/

SELECT pg_catalog.pg_extension_config_dump('public.roles', '');
SELECT pg_catalog.pg_extension_config_dump('public.roles_id_seq', '');
SELECT pg_catalog.pg_extension_config_dump('public.servers', '');
SELECT pg_catalog.pg_extension_config_dump('public.servers_id_seq', '');
SELECT pg_catalog.pg_extension_config_dump('public.services', '');
SELECT pg_catalog.pg_extension_config_dump('public.services_id_seq', '');
SELECT pg_catalog.pg_extension_config_dump('public.graphs', '');
SELECT pg_catalog.pg_extension_config_dump('public.graphs_id_seq', '');
SELECT pg_catalog.pg_extension_config_dump('public.series', '');
SELECT pg_catalog.pg_extension_config_dump('public.metrics', '');
SELECT pg_catalog.pg_extension_config_dump('public.metrics_id_seq', '');

/***************************************
*
* Create extension's functions
*
***************************************/

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

COMMENT ON FUNCTION public.create_account (IN text, OUT bigint, OUT text) IS 'Create a new OPM account.

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

ALTER FUNCTION public.create_user(IN text, IN text, IN name[], OUT bigint, OUT text)
    OWNER TO opm;
REVOKE ALL ON FUNCTION public.create_user(IN text, IN text, IN name[], OUT bigint, OUT text)
    FROM public;
GRANT ALL ON FUNCTION public.create_user(IN text, IN text, IN name[], OUT bigint, OUT text)
    TO opm_admins;

COMMENT ON FUNCTION public.create_user (IN p_user text, IN p_passwd text, IN p_accounts name[],
                    OUT rc boolean) IS 'Create a new OPM user for an OPM account.

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

COMMENT ON FUNCTION public.drop_account(IN name) IS 'Drop an existing OPM account.

It drops the account and also OPM roles that are only in this account.';

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

COMMENT ON FUNCTION public.drop_user(IN name) IS 'Drop an existing OPM user.';

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
                AND pg_has_role(a.rolname,'opm_roles','MEMBER')
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

    IF NOT public.is_admin(session_user) THEN
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
GRANT ALL ON FUNCTION public.list_users(name) TO opm_roles;

COMMENT ON FUNCTION public.list_users(name) IS 'List OPM users.

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
    IF NOT public.is_admin(session_user) THEN
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
GRANT EXECUTE ON FUNCTION public.list_accounts() TO opm_roles;

COMMENT ON FUNCTION public.list_accounts() IS 'List OPM accounts.

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
GRANT ALL ON FUNCTION public.is_user(IN name, OUT boolean) TO opm_roles;

COMMENT ON FUNCTION public.is_user(IN name, OUT boolean) IS 'Tells if the given rolname is an OPM user.';

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
GRANT ALL ON FUNCTION public.is_account(IN name, OUT boolean) TO opm_roles;

COMMENT ON FUNCTION public.is_account(IN name, OUT boolean) IS 'Tells if the given rolname is an OPM account.';

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
GRANT EXECUTE ON FUNCTION public.is_admin(IN name, OUT boolean) TO opm_roles;

COMMENT ON FUNCTION public.is_admin(IN name, OUT boolean) IS 'Tells if the given rolname is an OPM admin.';

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
GRANT ALL ON FUNCTION public.is_opm_role(IN name, OUT oid, OUT bigint, OUT name, OUT boolean) TO opm_roles;

COMMENT ON FUNCTION public.is_opm_role(IN name, OUT oid, OUT bigint, OUT name, OUT boolean) IS
'If given role exists as an OPM role (account or user), returns true.';

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
GRANT ALL ON FUNCTION public.wh_exists(IN name, OUT boolean) TO opm_roles;

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
GRANT ALL ON FUNCTION public.pr_exists(IN name, OUT boolean) TO opm_roles;

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
    IF public.is_admin(session_user) THEN
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
GRANT EXECUTE ON FUNCTION public.list_servers() TO opm_roles;

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
GRANT EXECUTE ON FUNCTION public.list_services() TO opm_roles;

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
    IF ( (public.is_admin(session_user)) OR (pg_has_role(session_user, p_accountname, 'MEMBER')) )THEN
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
GRANT EXECUTE ON FUNCTION public.grant_account(p_rolname name, p_accountname name) TO opm_admins;

COMMENT ON FUNCTION public.grant_account(p_rolname name, p_accountname name) IS 'Grant an OPM account to an OPM user.';


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
    IF ( (NOT public.is_user(p_rolname)) OR (NOT is_account(p_accountname)) ) THEN
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

    IF ( (public.is_admin(session_user)) OR (pg_has_role(session_user, p_accountname, 'MEMBER')) )THEN
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
GRANT EXECUTE ON FUNCTION public.revoke_account(p_rolname name, p_accountname name) TO opm_roles;

COMMENT ON FUNCTION public.revoke_account(p_rolname name, p_accountname name) IS 'Revoke an OPM account from an OPM user.';

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
GRANT EXECUTE ON FUNCTION public.list_warehouses() TO opm_roles;

COMMENT ON FUNCTION public.list_warehouses() IS 'List all warehouses.';

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
GRANT EXECUTE ON FUNCTION public.list_processes() TO opm_roles;

COMMENT ON FUNCTION public.list_processes() IS 'List all processes.';

/* public.update_user
Change the password of an opm user.

Can only be executed by roles opm and opm_admins.

@p_rolname: user to update
@p_password: new password
@return : true if everything went well
*/
CREATE OR REPLACE FUNCTION
    public.update_user(IN p_rolname name, IN p_password text)
    RETURNS boolean
AS $$
DECLARE
    v_exists boolean;
    v_state      text ;
    v_msg        text ;
    v_detail     text ;
    v_hint       text ;
    v_context    text ;
BEGIN
    SELECT true INTO v_exists FROM public.list_users()
    WHERE rolname = p_rolname LIMIT 1;
    IF NOT v_exists THEN
        RETURN false ;
    END IF ;
    EXECUTE format('ALTER ROLE %I WITH ENCRYPTED PASSWORD %L', p_rolname, p_password);
    RETURN true ;
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
END
$$
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER ;

ALTER FUNCTION public.update_user(IN name, IN text)
    OWNER TO opm ;
REVOKE ALL ON FUNCTION public.update_user(IN name, IN text)
    FROM public ;
GRANT ALL ON FUNCTION public.update_user(IN name, IN text)
    TO opm_admins ;

COMMENT ON FUNCTION public.update_user (IN name, IN text) IS
'Change the password of an opm user.' ;

CREATE OR REPLACE FUNCTION
  public.update_current_user(text)
  RETURNS boolean
AS $$
    SELECT public.update_user(current_user, $1);
$$
LANGUAGE sql
VOLATILE
LEAKPROOF;

ALTER FUNCTION public.update_current_user(text)
    OWNER TO opm ;
REVOKE ALL ON FUNCTION public.update_current_user(text)
    FROM public ;
GRANT ALL ON FUNCTION public.update_current_user(text)
    TO opm_roles;

COMMENT ON FUNCTION public.update_current_user(text) IS
'Change the password of the current opm user.' ;

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
