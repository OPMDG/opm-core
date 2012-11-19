SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;
SET search_path = public, pg_catalog;

-- CREATE ROLE pgfactory CREATEROLE;
-- CREATE ROLE pgf_admins CREATEROLE;

\c postgres
DROP DATABASE IF EXISTS pgfactory;
CREATE DATABASE pgfactory OWNER pgfactory;
\c pgfactory

CREATE TABLE public.services (
    id bigserial PRIMARY KEY,
    hostname text NOT NULL,
    warehouse text NOT NULL,
    service text NOT NULL,
    label text NOT NULL,
    last_modified date DEFAULT (now())::date NOT NULL,
    creation_ts timestamp with time zone DEFAULT now() NOT NULL,
    servalid interval,
    seracl aclitem[] NOT NULL
);
CREATE UNIQUE INDEX idx_services_hostname_service_label
    ON services USING btree (hostname, service, label);
ALTER TABLE public.services OWNER TO pgfactory;
REVOKE ALL ON TABLE public.services FROM public ;

CREATE TABLE public.accounts (
    id bigserial PRIMARY KEY,
    accname text NOT NULL,
    creation_ts timestamp with time zone DEFAULT now() NOT NULL,
    accconfig text[]
);
ALTER TABLE public.accounts OWNER TO pgfactory;
REVOKE ALL ON TABLE public.accounts FROM public ;

/* public.create_account
Create a new role (NOLOGIN) and register it in the public.accounts table.

Can only be executed by roles pgfactory and pgf_admins.

@return id: id of the new account.
@return name: name of the new account.
*/
CREATE OR REPLACE FUNCTION public.create_account(IN p_account text, OUT id bigint, OUT accname text)
    LANGUAGE plpgsql
    AS $$
    BEGIN
        EXECUTE 'CREATE ROLE ' || quote_ident(p_account);
        INSERT INTO public.accounts (accname) VALUES (p_account)
            RETURNING accounts.id, accounts.accname
                INTO create_account.id, create_account.accname;
    END
    $$
    VOLATILE
    LEAKPROOF
    SECURITY DEFINER;
ALTER FUNCTION public.create_account(IN text, OUT bigint, OUT text)
    OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.create_account(IN text, OUT bigint, OUT text)
    FROM public;
GRANT ALL ON FUNCTION public.create_account(IN text, OUT bigint, OUT text)
    TO pgf_admins;

/* public.create_role
Create a new user for an account.

Can only be executed by roles pgfactory and pgf_admins.

@return 
*/
CREATE OR REPLACE FUNCTION public.create_role(IN p_role text, IN p_accounts name[], OUT rc boolean)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
    DECLARE
        p_account name;
    BEGIN
        EXECUTE 'CREATE ROLE ' || quote_ident(p_role) || ' LOGIN';
        
        FOREACH p_account IN ARRAY p_accounts
        LOOP
            EXECUTE 'GRANT ' || quote_ident(p_account)
                || ' TO ' || quote_ident(p_role);
        END LOOP;

        rc := 't';
    END
    $$
    VOLATILE
    LEAKPROOF
    SECURITY DEFINER;
ALTER FUNCTION public.create_role(IN text, IN name[], OUT boolean)
    OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.create_role(IN text, IN name[], OUT boolean)
    FROM public;
GRANT ALL ON FUNCTION public.create_role(IN text, IN name[], OUT boolean)
    TO pgf_admins;


/* public.create_role
Create a new user for an account.

Can only be executed by roles pgfactory and pgf_admins.

@return 
*/
CREATE OR REPLACE FUNCTION public.list_roles()
    RETURNS TABLE (accname text, rolname name)
    LANGUAGE plpgsql
    AS $$
    DECLARE
        p_is_admin boolean;
    BEGIN
        SELECT pg_has_role('pgf_admins', 'MEMBER') INTO p_is_admin ;
        IF p_is_admin THEN
            RETURN QUERY WITH
                rol_acc AS (
                    SELECT acc.accname
                    FROM public.accounts AS acc
                    JOIN pg_catalog.pg_roles AS rol
                        ON (acc.accname=rol.rolname)
                )
                SELECT acc.accname, rol.rolname
                FROM pg_catalog.pg_roles AS rol
                JOIN rol_acc AS acc
                    ON (pg_has_role(rol.rolname, acc.accname, 'MEMBER')
                        AND acc.accname <> rol.rolname)
                WHERE rol.rolname <> 'postgres';
        ELSE
            RETURN QUERY WITH
                rol_acc AS (
                    SELECT acc.accname
                    FROM public.accounts AS acc
                    JOIN pg_catalog.pg_roles AS rol
                        ON (acc.accname=rol.rolname)
                    WHERE pg_has_role(acc.accname, 'MEMBER')
                )
                SELECT acc.accname, rol.rolname
                FROM pg_catalog.pg_roles AS rol
                JOIN rol_acc AS acc
                    ON (pg_has_role(rol.rolname, acc.accname, 'MEMBER')
                        AND acc.accname <> rol.rolname)
                WHERE rol.rolname <> 'postgres';
        END IF;
    END
    $$
    VOLATILE
    LEAKPROOF
    SECURITY DEFINER;
ALTER FUNCTION public.list_roles() OWNER TO pgfactory;
REVOKE ALL ON FUNCTION public.list_roles() FROM public;
GRANT ALL ON FUNCTION public.list_roles() TO pgf_admins;