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
DROP DATABASE IF EXISTS pgfactory;
DROP ROLE IF EXISTS pgfactory;
DROP ROLE IF EXISTS pgf_admins;
DROP ROLE IF EXISTS pgf_roles;
*/

CREATE ROLE pgfactory CREATEROLE;
CREATE ROLE pgf_admins CREATEROLE;
CREATE ROLE pgf_roles;
GRANT pgfactory TO pgf_admins;

/*
CREATE DATABASE pgfactory OWNER pgfactory;
\c pgfactory
*/

CREATE TABLE public.services (
    id bigserial PRIMARY KEY,
    hostname text NOT NULL,
    warehouse text NOT NULL,
    service text NOT NULL,
    last_modified date DEFAULT (now())::date NOT NULL,
    creation_ts timestamp with time zone DEFAULT now() NOT NULL,
    last_cleanup timestamp with time zone DEFAULT now() NOT NULL,
    oldest_record timestamp with time zone DEFAULT now(),
    newest_record timestamp with time zone,
    servalid interval,
    seracl aclitem[] NOT NULL DEFAULT '{}'::aclitem[]
);
CREATE UNIQUE INDEX idx_services_hostname_service_label
    ON services USING btree (hostname, service);
ALTER TABLE public.services OWNER TO pgfactory;
REVOKE ALL ON TABLE public.services FROM public ;

COMMENT ON TABLE public.services IS 'Table services lists all available metrics.

This table is a master table. Each warehouse have a specific services tables inherited from this master table';

COMMENT ON COLUMN public.services.id IS 'Service unique identifier. Is the primary key';
COMMENT ON COLUMN public.services.hostname IS 'hostname that provides this specific metric';
COMMENT ON COLUMN public.services.warehouse IS 'warehouse that stores this specific metric';
COMMENT ON COLUMN public.services.service IS 'service name that provides a specific metric';
COMMENT ON COLUMN public.services.last_modified IS 'last day that the dispatcher pushed datas in the warehouse';
COMMENT ON COLUMN public.services.creation_ts IS 'warehouse creation date and time for this particular hostname/service';
COMMENT ON COLUMN public.services.servalid IS 'data retention time';
COMMENT ON COLUMN public.services.seracl IS 'ACL on a particulier service';

-- Map properties and info between accounts/users and internal pgsql roles
CREATE TABLE public.roles (
    id bigserial PRIMARY KEY,
    rolname text NOT NULL,
    creation_ts timestamp with time zone DEFAULT now() NOT NULL,
    rolconfig text[]
);
CREATE UNIQUE INDEX idx_roles_rolname
    ON roles USING btree (rolname);
ALTER TABLE public.roles OWNER TO pgfactory;
REVOKE ALL ON TABLE public.roles FROM public ;

COMMENT ON TABLE public.roles IS 'Map properties and info between accounts/users and internal pgsql roles';

COMMENT ON COLUMN public.roles.id IS 'Role uniquer identier. Is the primary key of table roles';
COMMENT ON COLUMN public.roles.rolname IS 'rolname, same as rolname from table pg_roles';
COMMENT ON COLUMN public.roles.creation_ts IS 'Role creation date and time';
COMMENT ON COLUMN public.roles.rolconfig IS 'Specific configuration for a particular role';

/* public.create_account
Create a new account.

It creates a role (NOLOGIN) and register it in the public.accounts table.

TODO: grant the account to pgf_admins and pgfactory ?

Can only be executed by roles pgfactory and pgf_admins.

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
    EXECUTE format('GRANT pgf_roles TO %I', p_account);
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
    OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.create_account(IN text, OUT bigint, OUT text)
    FROM public;
GRANT ALL ON FUNCTION public.create_account(IN text, OUT bigint, OUT text)
    TO pgf_admins;

COMMENT ON FUNCTION public.create_account (IN text, OUT bigint, OUT text) IS 'Create a new account.

It creates a role (NOLOGIN) and register it in the public.roles table.

TODO: grant the account to pgf_admins and pgfactory ?

Can only be executed by roles pgfactory and pgf_admins.

@return id: id of the new account.
@return name: name of the new account.';

/* public.create_user
Create a new user for an account.

It creates a role (LOGIN, ENCRYPTED PASSWORD) and register it in the
public.roles table.

The p_accounts MUST have at least one account. We don't want user with no
accounts.

Can only be executed by roles pgfactory and pgf_admins.

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

    FOREACH p_account IN ARRAY p_accounts
    LOOP
        EXECUTE format('GRANT %I TO %I', p_account, p_user);
    END LOOP;

    EXECUTE format('GRANT pgf_roles TO %I', p_user);

    INSERT INTO public.roles (rolname) VALUES (p_user) RETURNING roles.id, roles.rolname
        INTO create_user.id, create_user.usename;
END
$$
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.create_user(IN text, IN text, IN name[], OUT boolean)
    OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.create_user(IN text, IN text, IN name[], OUT boolean)
    FROM public;
GRANT ALL ON FUNCTION public.create_user(IN text, IN text, IN name[], OUT boolean)
    TO pgf_admins;

COMMENT ON FUNCTION public.create_user (IN p_user text, IN p_passwd text, IN p_accounts name[],
                    OUT rc boolean) IS 'Create a new user for an account.

It creates a role (LOGIN, ENCRYPTED PASSWORD) and register it in the
public.roles table.

The p_accounts MUST have at least one account. We don''t want user with no
accounts.

Can only be executed by roles pgfactory and pgf_admins.

@return id: id of the new account.
@return name: name of the new account.';

/*public.drop_account

Drop an account.

Also drop all roles that are connected only to this particular account.

@return rolname: name of the dropped roles
*/
CREATE OR REPLACE FUNCTION
public.drop_account(IN p_account name)
 RETURNS SETOF text
AS $$
-- It drops an account and also roles that are only in this account.
DECLARE
        rolname name;
BEGIN
    /* get list of roles to drop with the account.
     * don't drop roles that are part of several accounts
     */
    IF (is_account(p_account) = false) THEN
      /* or do we raise an exception ? */
      RETURN;
    END IF;

    FOR rolname IN EXECUTE
        'SELECT t.rolname FROM (
            SELECT u.rolname, count(*)
            FROM pg_roles AS u
                JOIN pg_auth_members AS am ON (am.member = u.oid)
                JOIN pg_catalog.pg_roles AS a ON (a.oid = am.roleid)
            WHERE pg_has_role(u.oid, $1, ''MEMBER'')
                AND u.rolname NOT IN (''postgres'', $2)
                AND a.rolname <> ''pgf_roles''
            GROUP BY 1
        ) AS t
        WHERE t.count = 1' USING p_account, p_account
    LOOP
        EXECUTE format('SELECT drop_user(%L)', rolname);
        RETURN NEXT rolname;
    END LOOP;

    EXECUTE format('DELETE FROM public.roles WHERE rolname = %L', p_account);
    EXECUTE format('DROP ROLE %I', p_account);

    RETURN NEXT p_account;

    RETURN;
END;
$$
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.drop_account (IN name)
    OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.drop_account (IN name)
    FROM public;
GRANT ALL ON FUNCTION public.drop_account (IN name)
    TO pgf_admins;

COMMENT ON FUNCTION public.drop_account(IN name) IS 'Drop an account.

It drops an account and also roles that are only in this account.';

/*public.drop_account

Drop an account.

Also drop all roles that are connected only to this particular account.

@return rc: return code.
*/
CREATE OR REPLACE FUNCTION
public.drop_user(IN p_user name, OUT id bigint, OUT rolname name)
AS $$
DECLARE
        p_rolname name;
-- It drops an account and also roles that are only in this account.
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
    OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.drop_user (IN name)
    FROM public;
GRANT ALL ON FUNCTION public.drop_user (IN name)
    TO pgf_admins;

COMMENT ON FUNCTION public.drop_user(IN name) IS 'Drop a user.';

/* public.list_users
*/
CREATE OR REPLACE FUNCTION public.list_users()
    RETURNS TABLE (accname text, rolname name)
AS $$
BEGIN
    IF pg_has_role(session_user, 'pgf_admins', 'MEMBER') THEN
        RETURN QUERY WITH
            role_users AS (
                SELECT users.rolname
                FROM public.roles AS users
                JOIN pg_catalog.pg_roles AS rol ON (users.rolname=rol.rolname)
            )
            SELECT u.rolname, rol.rolname
            FROM pg_catalog.pg_roles AS rol
            JOIN role_users AS u
                ON (pg_has_role(rol.rolname, u.rolname, 'MEMBER')
                    AND u.rolname <> rol.rolname)
            WHERE NOT rol.rolsuper;
    ELSE
        RETURN QUERY WITH
            role_users AS (
                SELECT users.rolname
                FROM public.roles AS users
                JOIN pg_catalog.pg_roles AS rol
                    ON (users.rolname=rol.rolname)
                WHERE pg_has_role(session_user, users.rolname, 'MEMBER')
            )
            SELECT u.rolname, rol.rolname
            FROM pg_catalog.pg_roles AS rol
            JOIN role_users AS u
                ON (pg_has_role(rol.rolname, u.rolname, 'MEMBER')
                    AND u.rolname <> rol.rolname)
            WHERE NOT rol.rolsuper;
    END IF;
END
$$
LANGUAGE plpgsql
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.list_users() OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.list_users() FROM public;
GRANT ALL ON FUNCTION public.list_users() TO public;

COMMENT ON FUNCTION public.list_users() IS 'List users.

If current user is member of pgf_admins, list all users and account on the system.

If current user is not admin, list all users and account who are related to the current user.';

/*
is_pgf_role(rolname)

@return: if given role exists as a pgFactory role (account or user), returns its
oid, id, name and canlogin attributes. NULL if not exists or not a pgFactory
role.
 */
CREATE OR REPLACE FUNCTION public.is_pgf_role(IN p_rolname name, OUT oid oid, OUT id bigint, OUT rolname name, OUT rolcanlogin boolean)
AS $$
    SELECT acc.oid, roles.id, acc.rolname, acc.rolcanlogin
    FROM public.roles roles
        JOIN pg_catalog.pg_roles acc ON (acc.rolname = roles.rolname)
    WHERE roles.rolname = p_rolname
$$
LANGUAGE SQL
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.is_pgf_role(IN name, OUT oid, OUT bigint, OUT name, OUT boolean) OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.is_pgf_role(IN name, OUT oid, OUT bigint, OUT name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.is_pgf_role(IN name, OUT oid, OUT bigint, OUT name, OUT boolean) TO public;

COMMENT ON FUNCTION public.is_pgf_role(IN name, OUT oid, OUT bigint, OUT name, OUT boolean) IS
'If given role exists as a pgFactory role (account or user), returns its name
and canlogin attributes. Nothing if not exists or not a pgFactory role';

/*
is_user(rolname)

@return rc: true if the given rolname is a simple user
 */
CREATE OR REPLACE FUNCTION public.is_user(IN p_rolname name, OUT rc boolean)
AS $$
    SELECT CASE (public.is_pgf_role(p_rolname)).rolcanlogin
        WHEN true THEN true
        WHEN false THEN false
        ELSE NULL
    END;
$$
LANGUAGE SQL
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.is_user(IN name, OUT boolean) OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.is_user(IN name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.is_user(IN name, OUT boolean) TO public;

COMMENT ON FUNCTION public.is_user(IN name, OUT boolean) IS 'Tells if the given rolname is a user.';

/*
is_account(rolname)

@return rc: true if the given rolname is an account


--- retourne NULL si inexistant
 */
CREATE OR REPLACE FUNCTION public.is_account(IN p_rolname name, OUT rc boolean)
AS $$
    SELECT CASE NOT (public.is_pgf_role(p_rolname)).rolcanlogin
        WHEN true THEN true
        WHEN false THEN false
        ELSE NULL
    END;
$$
LANGUAGE SQL
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.is_account(IN name, OUT boolean) OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.is_account(IN name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.is_account(IN name, OUT boolean) TO public;

COMMENT ON FUNCTION public.is_account(IN name, OUT boolean) IS 'Tells if the given rolname is an account.';

/*
wh_exists(wh)

@return rc: true if the given warehouse exists
 */
CREATE OR REPLACE FUNCTION public.wh_exists(IN p_whname name, OUT rc boolean)
AS $$
    SELECT count(*) > 0
    FROM pg_catalog.pg_namespace
    WHERE nspname = $1;
$$
LANGUAGE SQL
STABLE
LEAKPROOF;

ALTER FUNCTION public.wh_exists(IN name, OUT boolean) OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.wh_exists(IN name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.wh_exists(IN name, OUT boolean) TO public;

COMMENT ON FUNCTION public.wh_exists(IN name, OUT boolean) IS 'Returns true if the given warehouse exists.';

/*
public.grant_dispatcher(wh, role)

@return rc: state of the operation
 */
CREATE OR REPLACE FUNCTION public.grant_dispatcher(IN p_whname text, IN p_rolname name, OUT rc boolean)
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

ALTER FUNCTION public.grant_dispatcher(IN text, IN name, OUT boolean) OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.grant_dispatcher(IN text, IN name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.grant_dispatcher(IN text, IN name, OUT boolean) TO pgf_admins;

COMMENT ON FUNCTION public.grant_dispatcher(IN text, IN name, OUT boolean)
IS 'Grant a role to dispatch performance data in a warehouse hub table.';

/*
public.revoke_dispatcher(wh, role)

@return rc: state of the operation
 */
CREATE OR REPLACE FUNCTION public.revoke_dispatcher(IN p_whname text, IN p_rolname name, OUT rc boolean)
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

ALTER FUNCTION public.revoke_dispatcher(IN text, IN name, OUT boolean) OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.revoke_dispatcher(IN text, IN name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.revoke_dispatcher(IN text, IN name, OUT boolean) TO pgf_admins;

COMMENT ON FUNCTION public.revoke_dispatcher(IN text, IN name, OUT boolean) IS 'Revoke dispatch ability for a give role on a given hub table.';

/*
public.grant_service(service, role)

@return rc: status
 */
CREATE OR REPLACE FUNCTION public.grant_service(IN p_service_id bigint, IN p_rolname name, OUT rc boolean)
AS $$
DECLARE
        v_state      text;
        v_msg        text;
        v_detail     text;
        v_hint       text;
        v_context    text;
        v_whname     text;
        v_is_acl_empty boolean;

        v_sql        text;
BEGIN
/* verify that the give role exists */
    BEGIN
        EXECUTE format('SELECT true FROM public.roles WHERE rolname = %L', p_rolname) INTO STRICT rc;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE NOTICE 'Given role is not a PGFactory role %', p_rolname;
            rc := false;
            RETURN;
    END;

    /* which warehouse ? */
    EXECUTE format('SELECT warehouse FROM services WHERE id = %L', p_service_id) INTO v_whname;

    /* verify that the given warehouse exists */
    DECLARE
        spc oid;
    BEGIN
        EXECUTE format('SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = %L', v_whname) INTO STRICT spc;
        EXECUTE format('SELECT true FROM pg_catalog.pg_class WHERE relname = ''hub'' AND relnamespace = %L', spc) INTO STRICT rc;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE NOTICE 'Given warehouse does not exists: %', v_whname;
            rc := false;
            RETURN;
    END;

        /* avoid the following error if seracl is empty: ACL arrays must be one-dimensional */
    EXECUTE format('
        SELECT CASE
                WHEN array_dims(seracl) IS NULL THEN true
                ELSE false
            END AS is_acl_empty
        FROM services WHERE id = %L', p_service_id
    ) INTO v_is_acl_empty;

    IF v_is_acl_empty = true THEN
        EXECUTE format('UPDATE services
            SET seracl = seracl || aclitemin(%L)
            WHERE id = %L', p_rolname || '=r/pgfactory', p_service_id
        );
    ELSE
        /* update ACL in the service table */
        EXECUTE format('UPDATE services
            SET seracl = seracl || aclitemin(%L)
            WHERE NOT aclcontains(seracl, aclitemin(%L))
                AND id = %L',
            p_rolname || '=r/pgfactory',
            p_rolname || '=r/pgfactory',
            p_service_id
        );
    END IF;

    /* put the ACL on the partition, let the warehouse function do it */
    v_sql := format('SELECT %I.grant_service(%L)', v_whname, p_service_id);

    RAISE NOTICE 'SQL: %', v_sql;
    RAISE NOTICE 'UNFINISHED ! Need to determine an API between core and wh to give rights on a service data';
    rc := false;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state   = RETURNED_SQLSTATE,
            v_msg     = MESSAGE_TEXT,
            v_detail  = PG_EXCEPTION_DETAIL,
            v_hint    = PG_EXCEPTION_HINT,
            v_context = PG_EXCEPTION_CONTEXT;
        raise notice E'Unhandled error:
            state  : %
            message: %
            detail : %
            hint   : %
            context: %', v_state, v_msg, v_detail, v_hint, v_context;
        rc := false;
END;
$$
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.grant_service(IN p_service_id bigint, IN p_rolname name, OUT rc boolean) OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.grant_service(IN p_service_id bigint, IN p_rolname name, OUT rc boolean) FROM public;
GRANT ALL ON FUNCTION public.grant_service(IN p_service_id bigint, IN p_rolname name, OUT rc boolean) TO pgf_admins;

COMMENT ON FUNCTION public.grant_service(IN p_service_id bigint, IN p_rolname name, OUT rc boolean) IS 'Grant SELECT on a service.';

/*
public.revoke_service(service, role)

@return rc: status
 */
CREATE OR REPLACE FUNCTION public.revoke_service(IN p_service_id bigint, IN p_rolname name, OUT rc boolean)
AS $$
DECLARE
        v_state      text;
        v_msg        text;
        v_detail     text;
        v_hint       text;
        v_context    text;
        v_whname     text;
        v_is_acl_empty boolean;
        v_acl_exists   boolean;
        v_acl_last_element boolean;
        v_seracl     aclitem[];

        v_sql        text;
BEGIN
/* verify that the give role exists */
    BEGIN
        EXECUTE format('SELECT true FROM public.roles WHERE rolname = %L', p_rolname) INTO STRICT rc;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE NOTICE 'Given role is not a PGFactory role %', p_rolname;
            rc := false;
            RETURN;
    END;

    /* which warehouse ? */
    EXECUTE format('SELECT warehouse FROM services WHERE id = %L', p_service_id) INTO v_whname;

    /* verify that the given warehouse exists */
    DECLARE
        spc oid;
    BEGIN
        EXECUTE format('SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = %L', v_whname) INTO STRICT spc;
        EXECUTE format('SELECT true FROM pg_catalog.pg_class WHERE relname = ''hub'' AND relnamespace = %L', spc) INTO STRICT rc;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE NOTICE 'Given warehouse does not exists: %', v_whname;
            rc := false;
            RETURN;
    END;

    /* avoid the following error if seracl is empty: ACL arrays must be one-dimensional */
    EXECUTE format('SELECT
                CASE
                    WHEN array_dims(seracl) IS NULL THEN true
                    ELSE false
                END AS is_acl_empty
            FROM services WHERE id = %L',
        p_service_id
    ) INTO v_is_acl_empty;

    IF v_is_acl_empty = true THEN
        RAISE NOTICE 'ACL is empty';
        rc := false;
        RETURN;
    ELSE
        /* does the ACL exists ? */
        EXECUTE format('SELECT
                    CASE
                        WHEN aclcontains(seracl, aclitemin(%L)) THEN true
                        ELSE false
                    END
                FROM services
                WHERE id = %L',
            p_rolname || '=r/pgfactory', p_service_id
        ) INTO v_acl_exists;

        IF v_acl_exists = false THEN
            RAISE NOTICE 'ACL does not exists';
            rc := false;
            RETURN;
        END IF;

        /* if the ACL is the last remaining one, then put an empty ACL directly. Otherwise, execute the CTE to do the right update */
        EXECUTE format('SELECT
                CASE
                    WHEN array_length(seracl, 1) = 1 THEN true
                    ELSE false
                END AS is_acl_empty
            FROM services
            WHERE id = %L', p_service_id
        ) INTO v_acl_last_element;

        IF v_acl_last_element = true THEN
            RAISE NOTICE 'last element';
            EXECUTE format('UPDATE services
                SET seracl = ARRAY[]::aclitem[]
                WHERE id = %L', p_service_id
            );

        ELSE
            EXECUTE format('WITH
                    explode_seracl AS (
                        SELECT id, unnest(seracl) AS acl
                            FROM services
                        WHERE id = %L
                    ),
                    filter_acl AS (
                        SELECT id, array_agg(acl) AS acl
                            FROM explode_seracl
                        WHERE
                            -- ACL to remove is filtered
                            NOT aclitemeq(acl,  aclitemin(%L))
                        GROUP BY id
                    )
                    UPDATE services
                    SET seracl=acl
                    FROM filter_acl
                    WHERE services.id=filter_acl.id -- then ACL is rewritten',
                p_service_id,
                p_rolname || '=r/pgfactory'
            );
        END IF;
    END IF;

    /* put the ACL on the partition, let the warehouse function do it */
    v_sql := format('SELECT %I.revoke_service(%L)', v_whname, p_service_id);

    RAISE NOTICE 'SQL: %', v_sql;
    RAISE NOTICE 'UNFINISHED ! Need to determine an API between core and wh to give rights on a service data';
    rc := false;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state   = RETURNED_SQLSTATE,
            v_msg     = MESSAGE_TEXT,
            v_detail  = PG_EXCEPTION_DETAIL,
            v_hint    = PG_EXCEPTION_HINT,
            v_context = PG_EXCEPTION_CONTEXT;
        raise notice E'Unhandled error:
            state  : %
            message: %
            detail : %
            hint   : %
            context: %', v_state, v_msg, v_detail, v_hint, v_context;
        rc := false;
END;
$$
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.revoke_service(IN p_service_id bigint, IN p_rolname name, OUT rc boolean) OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.revoke_service(IN p_service_id bigint, IN p_rolname name, OUT rc boolean) FROM public;
GRANT ALL ON FUNCTION public.revoke_service(IN p_service_id bigint, IN p_rolname name, OUT rc boolean) TO pgf_admins;

COMMENT ON FUNCTION public.revoke_service(IN p_service_id bigint, IN p_rolname name, OUT rc boolean) IS 'Grant SELECT on a service.';

/*
list_services()
 */
CREATE OR REPLACE FUNCTION public.list_services()
    RETURNS TABLE (id bigint, hostname text, warehouse text, service text, last_modified date, creation_ts timestamp with time zone, servalid interval)
AS $$
BEGIN
    IF pg_has_role(session_user, 'pgf_admins', 'MEMBER') THEN
        RETURN QUERY SELECT s.id, s.hostname, s.warehouse,
                s.service, s.last_modified, s.creation_ts, s.servalid
            FROM services s;
    ELSE
        RETURN QUERY EXECUTE 'WITH RECURSIVE
                v_roles AS (
                    SELECT pr.oid AS oid, r.rolname, ARRAY[r.rolname] AS roles
                      FROM public.roles r
                      JOIN pg_catalog.pg_roles pr ON (r.rolname = pr.rolname)
                     WHERE r.rolname = $1
                    UNION ALL
                    SELECT pa.oid, v.rolname, v.roles|| pa.rolname::text
                      FROM v_roles v
                      JOIN pg_auth_members am ON (am.member = v.oid)
                      JOIN pg_roles pa ON (am.roleid = pa.oid)
                     WHERE NOT pa.rolname::name = ANY(v.roles)
                ),
                acl AS (
                    SELECT id, hostname, warehouse, service, last_modified,
                        creation_ts, servalid, (aclexplode(seracl)).*
                    FROM services
                    WHERE array_length(seracl, 1) IS NOT NULL
                )
                SELECT id, hostname, warehouse, service,
                    last_modified, creation_ts, servalid
                FROM acl
                WHERE grantee IN (SELECT oid FROM v_roles)' USING session_user;
    END IF;
END;
$$ LANGUAGE plpgsql
STABLE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.list_services() OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.list_services() FROM public;
GRANT ALL ON FUNCTION public.list_services() TO public;

COMMENT ON FUNCTION public.list_services() IS 'List services available for the session user.';

