SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;
SET search_path = public, pg_catalog;

\c postgres
DROP DATABASE IF EXISTS pgfactory;
DROP ROLE IF EXISTS pgfactory;
DROP ROLE IF EXISTS pgf_admins;
DROP ROLE IF EXISTS pgf_accounts;
CREATE ROLE pgfactory CREATEROLE;
CREATE ROLE pgf_admins CREATEROLE;
CREATE ROLE pgf_accounts;

CREATE DATABASE pgfactory OWNER pgfactory;
\c pgfactory

CREATE TABLE public.services (
    id bigserial PRIMARY KEY,
    hostname text NOT NULL,
    warehouse text NOT NULL,
    service text NOT NULL,
    last_modified date DEFAULT (now())::date NOT NULL,
    creation_ts timestamp with time zone DEFAULT now() NOT NULL,
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
    BEGIN
        EXECUTE format('CREATE ROLE %I', p_account);
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
                    OUT rc boolean)
AS $$
    DECLARE
        p_account name;
    BEGIN
        
        IF coalesce(array_length(p_accounts, 1), 0) < 1 THEN
            -- or maybe we should raise an exception ?
            RAISE WARNING 'A user must have at least one associated account!';
            rc := 'f';
            RETURN;
        END IF;

        EXECUTE format('CREATE ROLE %I LOGIN ENCRYPTED PASSWORD %L',
            p_user, p_passwd);
        
        FOREACH p_account IN ARRAY p_accounts
        LOOP
            EXECUTE format('GRANT %I TO %I', p_account, p_user);
        END LOOP;

        INSERT INTO public.roles (rolname) VALUES (p_user);

        rc := 't';
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
		FOR rolname IN EXECUTE 'SELECT roles_to_drop.rolname FROM (
						SELECT array_agg(am.roleid) AS oid, rol.rolname
						  FROM public.roles rol
						  JOIN pg_roles pgrol ON (pgrol.rolname = rol.rolname)
						  JOIN pg_auth_members am ON (am.member = pgrol.oid)
						 WHERE pgrol.rolcanlogin
						 GROUP BY 2
						 HAVING count(*) = 1
						) roles_to_drop
						JOIN pg_roles pgacc ON (pgacc.oid = ANY(roles_to_drop.oid))
						AND pgacc.rolname = ' || quote_literal(p_account)
		LOOP
			RAISE NOTICE 'role: %', rolname;
			EXECUTE 'SELECT drop_user(' || quote_literal(rolname) ||')';
			RETURN NEXT rolname;
		END LOOP;
		EXECUTE 'DELETE FROM public.roles WHERE rolname = ' || quote_literal(p_account);
		EXECUTE 'DROP ROLE ' || quote_ident(p_account);
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
public.drop_user(IN p_user name, OUT rc boolean)
AS $$
	DECLARE
		p_rolname name;
	-- It drops an account and also roles that are only in this account.
	BEGIN
	    IF (is_user(p_user) = false) THEN
	      rc := false;
	      /* or do we raise an exception ? */
	      RETURN;
	    END IF;
	    EXECUTE 'SELECT rolname FROM public.roles WHERE rolname = ' || quote_literal(p_user) INTO STRICT p_rolname;
		EXECUTE 'DELETE FROM public.roles WHERE rolname = ' || quote_literal(p_user);
		EXECUTE 'DROP ROLE ' || quote_ident(p_user);
		RAISE NOTICE 'User % dropped.', p_user;
		rc := true;
	EXCEPTION
		WHEN NO_DATA_FOUND THEN
			RAISE NOTICE 'Non-existent user %', p_user;
			rc := false;
		WHEN OTHERS THEN
			RAISE LOG 'Impossible to drop user: %', p_user;
			rc := false;
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
                    JOIN pg_catalog.pg_roles AS rol
                        ON (users.rolname=rol.rolname)
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
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.list_users() OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.list_users() FROM public;
GRANT ALL ON FUNCTION public.list_users() TO public;

COMMENT ON FUNCTION public.list_users() IS 'List users.

If current user is member of pgf_admins, list all users and account on the system.

If current user is not admin, list all users and account who are related to the current user.';

/*
is_user(rolname)

@return rc: true if the given rolname is a simple user
 */
CREATE OR REPLACE FUNCTION public.is_user(IN p_rolname name, OUT rc boolean)
AS $$
	BEGIN
		EXECUTE 'SELECT CASE WHEN roles.rolname IS NOT NULL THEN true ELSE false END
		  FROM public.roles roles
		  JOIN pg_roles acc ON (acc.rolname = roles.rolname)
		 WHERE acc.rolcanlogin
		   AND roles.rolname = ' || quote_literal(p_rolname) || '' INTO rc;
		IF (rc IS NULL) THEN
		  rc := false;
		END IF;
	END;
$$ 
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.is_user(IN name, OUT boolean) OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.is_user(IN name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.is_user(IN name, OUT boolean) TO public;

COMMENT ON FUNCTION public.is_user(IN name, OUT boolean) IS 'Tells if the given rolname is a user.';
 
/*
is_account(rolname)

@return rc: true if the given rolname is an account
 */
CREATE OR REPLACE FUNCTION public.is_account(IN p_rolname name, OUT rc boolean)
AS $$
	BEGIN
		EXECUTE 'SELECT CASE WHEN roles.rolname IS NOT NULL THEN true ELSE false END
		  FROM public.roles roles
		  JOIN pg_roles acc ON (acc.rolname = roles.rolname)
		 WHERE NOT acc.rolcanlogin
		   AND roles.rolname = ' || quote_literal(p_rolname) INTO rc;
		IF (rc IS NULL) THEN
		  rc := false;
		END IF;
	END;
$$ 
LANGUAGE plpgsql
VOLATILE
LEAKPROOF
SECURITY DEFINER;

ALTER FUNCTION public.is_account(IN name, OUT boolean) OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.is_account(IN name, OUT boolean) FROM public;
GRANT ALL ON FUNCTION public.is_account(IN name, OUT boolean) TO public;

COMMENT ON FUNCTION public.is_account(IN name, OUT boolean) IS 'Tells if the given rolname is an account.';
 
