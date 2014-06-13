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

REVOKE ALL ON SCHEMA public FROM public;

DO LANGUAGE plpgsql
$$
DECLARE
    v_dbname name := pg_catalog.current_database();
    v_dbaname name := r.rolname FROM pg_database AS d
         JOIN pg_roles AS r ON d.datdba = r.oid
         WHERE datname = pg_catalog.current_database();
BEGIN
    SELECT pg_catalog.current_database() INTO v_dbname;
    EXECUTE pg_catalog.format('REVOKE ALL ON DATABASE %I FROM public', v_dbname);
    EXECUTE pg_catalog.format('ALTER SCHEMA public OWNER TO %I', v_dbaname);
END
$$;

/***************************************
*
* Create extension's objects
*
***************************************/

CREATE TYPE public.metric_value AS (
    timet timestamp with time zone,
    value numeric
);

COMMENT ON TYPE public.metric_value IS
'Composite type to stored timestamped values from metrics perdata.
Every warehouse has to return its data with this type' ;

----------------------------------------------
-- API refrential table

CREATE TABLE public.api (
    proc regprocedure
);

----------------------------------------------
-- Application role definition
CREATE TABLE public.roles (
    id          bigserial PRIMARY KEY,
    rolname     text      NOT NULL,
    canlogin    boolean   NOT NULL DEFAULT 'f',
    password    text,
    creation_ts timestamp with time zone DEFAULT now() NOT NULL,
    rolconfig   text[],
    UNIQUE (rolname)
);

REVOKE ALL ON TABLE public.roles FROM public ;

COMMENT ON TABLE  public.roles             IS 'Available aplication roles (users and groups) that can access data.' ;
COMMENT ON COLUMN public.roles.id          IS 'Role unique identier. Is the primary key of table roles.' ;
COMMENT ON COLUMN public.roles.rolname     IS 'The role name.' ;
COMMENT ON COLUMN public.roles.creation_ts IS 'Role creation date and time.';
COMMENT ON COLUMN public.roles.canlogin    IS 'If set to false, the role is kind of a group.' ;
COMMENT ON COLUMN public.roles.password    IS 'Password of the rôle. This must be hashed' ;
COMMENT ON COLUMN public.roles.rolconfig   IS 'Specific configuration for given role.' ;

INSERT INTO public.roles (rolname) VALUES ('opm_admins');



----------------------------------------------
-- Role members
CREATE TABLE public.members (
    rolname text,
    member  text,
    PRIMARY KEY (rolname, member),
    UNIQUE (member, rolname),
    FOREIGN KEY (rolname) REFERENCES public.roles(rolname) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (member)  REFERENCES public.roles(rolname) ON DELETE CASCADE ON UPDATE CASCADE
);

REVOKE ALL ON TABLE public.members FROM public;

COMMENT ON TABLE  public.members         IS 'Membership relation between roles.';
COMMENT ON COLUMN public.members.rolname IS 'The role name.' ;
COMMENT ON COLUMN public.members.member  IS 'Role members.rolname is member of members.member';



----------------------------------------------
-- Servers
CREATE TABLE public.servers (
    id       bigserial PRIMARY KEY,
    hostname text      NOT NULL,
    id_role  bigint    REFERENCES public.roles (id) ON UPDATE CASCADE ON DELETE SET NULL,
    UNIQUE (hostname)
);

REVOKE ALL ON TABLE public.servers FROM public ;

COMMENT ON TABLE  public.servers          IS 'Table servers lists all referenced servers.' ;
COMMENT ON COLUMN public.servers.id       IS 'Server unique identifier. Is the primary key.' ;
COMMENT ON COLUMN public.servers.hostname IS 'Hostname of the server, as referenced by dispatcher. Must be unique.' ;
COMMENT ON COLUMN public.servers.id_role  IS 'Owner of the server.' ;



----------------------------------------------
-- Services
CREATE TABLE public.services (
    id            bigserial PRIMARY KEY,
    id_server     bigint    NOT NULL REFERENCES public.servers (id) ON UPDATE CASCADE ON DELETE CASCADE,
    warehouse     text      NOT NULL,
    service       text      NOT NULL,
    last_modified date      NOT NULL DEFAULT (now())::date,
    creation_ts   timestamp with time zone NOT NULL DEFAULT now(),
    last_cleanup  timestamp with time zone NOT NULL DEFAULT now(),
    servalid      interval,
    oldest_record timestamp with time zone,
    newest_record timestamp with time zone,
    UNIQUE (id_server, service)
);

REVOKE ALL ON TABLE public.services FROM public ;

COMMENT ON TABLE public.services IS
    'Table services lists all available metrics.

This table is a master table. Each warehouse have a specific services tables inherited from this master table.';

COMMENT ON COLUMN public.services.id            IS 'Service unique identifier. Is the primary key.';
COMMENT ON COLUMN public.services.id_server     IS 'Identifier of the server.';
COMMENT ON COLUMN public.services.warehouse     IS 'Warehouse that stores this specific metric.';
COMMENT ON COLUMN public.services.service       IS 'Service name that provides a specific metric.';
COMMENT ON COLUMN public.services.last_modified IS 'Last day that the dispatcher pushed datas in the warehouse.';
COMMENT ON COLUMN public.services.creation_ts   IS 'Warehouse creation date and time for this particular service.';
COMMENT ON COLUMN public.services.last_cleanup  IS 'Last launch of "warehouse".cleanup_service(). Each warehouse has to implement his own, if needed.';
COMMENT ON COLUMN public.services.servalid      IS 'Data retention time.';
COMMENT ON COLUMN public.services.oldest_record IS 'Timestamp of the oldest value stored for the service.';
COMMENT ON COLUMN public.services.newest_record IS 'Timestamp of the newest value stored for the service.';


----------------------------------------------
-- Metrics from services
CREATE TABLE public.metrics (
    id         bigserial PRIMARY KEY,
    id_service bigint,
    label      text,
    unit       text
);

REVOKE ALL ON TABLE public.metrics FROM public;

COMMENT ON TABLE  public.metrics            IS 'Define a metric. This table has to be herited in warehouses.';
COMMENT ON COLUMN public.metrics.id         IS 'Metric unique identifier.';
COMMENT ON COLUMN public.metrics.id_service IS 'References the warehouse.services unique identifier..' ;
COMMENT ON COLUMN public.metrics.label      IS 'Metric title.';
COMMENT ON COLUMN public.metrics.unit       IS 'Metric unit.';



----------------------------------------------
-- Graphs
CREATE TABLE public.graphs (
  id          bigserial PRIMARY KEY,
  graph       text      NOT NULL,
  description text,
  config      json
);

REVOKE ALL ON TABLE public.graphs FROM public ;

COMMENT ON TABLE  public.graphs             IS 'Store all graphs definitions.' ;
COMMENT ON COLUMN public.graphs.id          IS 'Graph unique identifier. Is the primary key of the table public.graphs.' ;
COMMENT ON COLUMN public.graphs.graph       IS 'Title of the graph.' ;
COMMENT ON COLUMN public.graphs.description IS 'Description of the graph.' ;
COMMENT ON COLUMN public.graphs.config      IS 'Specific flotr2 graph configuration, stored in json.' ;


----------------------------------------------
-- Series in graphs
CREATE TABLE public.series (
    id_graph  bigint,
    id_metric bigint,
    config    json
) ;

REVOKE ALL ON TABLE public.series FROM public ;

COMMENT ON TABLE  public.series           IS 'Define a serie. This table has to be herited in warehouses.' ;
COMMENT ON COLUMN public.series.id_graph  IS 'References graph unique identifier.' ;
COMMENT ON COLUMN public.series.id_metric IS 'References warehouse.metrics unique identifier.' ;
COMMENT ON COLUMN public.series.config    IS 'Specific flotr2 configuration for this serie.' ;




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


/*********** NOT API *************/
/*
These functions are available for manual use only. NOT from
an application.
*/

/* v2.1
 * public.register_api(name, name)
 * Add given function to the API function list
 * avaiable from application.
 */
CREATE OR REPLACE FUNCTION public.register_api(IN p_proc regprocedure,
    OUT proc regprocedure, OUT registered boolean)
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF
SET search_path TO public
AS $$
BEGIN
    INSERT INTO public.api VALUES (p_proc)
    RETURNING p_proc, true
        INTO register_api.proc, register_api.registered;
END
$$;

REVOKE ALL ON FUNCTION public.register_api(regprocedure) FROM public;

COMMENT ON FUNCTION public.register_api(regprocedure) IS
'Add given function to the API function list avaiable from application.';

/* v2.1
 * this function is only called by the extensions themselves
 *  to set the owner of their functions to the database owner.
 */
CREATE OR REPLACE
FUNCTION public.set_extension_owner(IN p_extname name)
RETURNS TABLE (owner name, objtype text, objname text)
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF
SET search_path TO public
AS $$
DECLARE
    v_nspname name := n.nspname
        FROM pg_extension AS e
            JOIN pg_namespace AS n ON e.extnamespace = n.oid
        WHERE e.extname = p_extname;
BEGIN
    owner := r.rolname FROM pg_database AS d
        JOIN pg_roles AS r ON d.datdba = r.oid
        WHERE datname = pg_catalog.current_database();

    FOR objtype, objname IN (
        SELECT i.type, i.identity
        FROM pg_catalog.pg_depend AS d
            JOIN pg_catalog.pg_extension AS e ON d.refobjid = e.oid,
            LATERAL pg_catalog.pg_identify_object(d.classid, d.objid, 0) AS i
        WHERE e.extname = p_extname
            AND d.refclassid = 'pg_catalog.pg_extension'::pg_catalog.regclass
            AND deptype = 'e'
            -- exclude this function. It always needs to belong to a superuser.
            AND i.identity !~ '^public.set_extension_owner'
    )
    LOOP
        -- warning: identity is already escaped by pg_identify_object(...)
        EXECUTE pg_catalog.format('ALTER %s %s OWNER TO %I', objtype, objname, owner);
        RETURN NEXT;
    END LOOP;

    EXECUTE pg_catalog.format('ALTER SCHEMA %I OWNER TO %I', v_nspname, owner);
    objtype := 'schema';
    objname := CAST (v_nspname AS text);

    RETURN NEXT;
END
$$;

REVOKE ALL ON FUNCTION public.set_extension_owner(IN name) FROM public;

COMMENT ON FUNCTION public.set_extension_owner(name) IS
'this function is only called by the extensions themselves to set the owner of their functions to the database owner.';

/* v2.1
public.admin(IN p_admin name, IN p_passwd text)

Create a new admin.

Can only be executed by its owner (usually, the one of this database)

This should only be called when setting up OPM.

@return id: id of the new admin.
@return name: name of the new admin.
*/
CREATE OR REPLACE
FUNCTION public.create_admin (IN p_admin text, IN p_passwd text,
    OUT bigint, OUT text)
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





/* v2.1
public.grant_appli
Grant a postgresql role to access our API.

@return granted: true if success
*/
CREATE OR REPLACE
FUNCTION public.grant_appli (IN p_role name)
RETURNS TABLE (operat text, approle name, appright text, objtype text, objname text)
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF
SET search_path TO public
AS $$
DECLARE
    v_dbname    name := pg_catalog.current_database();
    v_warehouse name;
    v_proname   regprocedure;
BEGIN
    operat   := 'GRANT';
    approle  := p_role;

    appright := 'CONNECT';
    objtype  := 'database';
    objname  := v_dbname;
    EXECUTE pg_catalog.format('GRANT %s ON %s %I TO %I', appright, objtype, objname, approle);

    RETURN NEXT;

    appright := 'USAGE';
    objtype  := 'schema';
    objname  := 'public';
    EXECUTE pg_catalog.format('GRANT %s ON %s %I TO %I', appright, objtype, objname, approle);

    RETURN NEXT;

    appright := 'EXECUTE';
    -- grant execute on API functions
    FOR v_proname IN (
        SELECT proc
        FROM public.api
    )
    LOOP
        EXECUTE pg_catalog.format('GRANT EXECUTE ON FUNCTION %s TO %I', v_proname, approle);
        objname := v_proname::text;
        RETURN NEXT;
    END LOOP;
END
$$;

REVOKE ALL ON FUNCTION public.grant_appli(IN name) FROM public;

COMMENT ON FUNCTION public.grant_appli(IN name) IS
'Grant a postgresql role to access OPM API';



/* v2.1
public.revoke_appli
Revoke a postgresql role to access our API.

@return granted: true if success
*/
CREATE OR REPLACE
FUNCTION public.revoke_appli (IN p_role name)
RETURNS TABLE (operat text, approle name, appright text, objtype text, objname text)
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF
SET search_path TO public
AS $$
DECLARE
    v_dbname    name := pg_catalog.current_database();
    v_warehouse name;
    v_proname   regprocedure;
BEGIN
    operat   := 'REVOKE';
    approle  := p_role;

    appright := 'CONNECT';
    objtype  := 'database';
    objname  := v_dbname;
    EXECUTE pg_catalog.format('REVOKE %s ON %s %I FROM %I', appright, objtype, objname, approle);

    RETURN NEXT;

    appright := 'USAGE';
    objtype  := 'schema';
    objname  := 'public';
    EXECUTE pg_catalog.format('REVOKE %s ON %s %I FROM %I', appright, objtype, objname, approle);

    RETURN NEXT;

    appright := 'EXECUTE';
    -- revoke execute on API functions
    FOR v_proname IN (
        SELECT proc
        FROM public.api
    )
    LOOP
        EXECUTE pg_catalog.format('REVOKE EXECUTE ON FUNCTION %s FROM %I', v_proname, approle);
        objname := v_proname::text;
        RETURN NEXT;
    END LOOP;
END
$$;

REVOKE ALL ON FUNCTION public.revoke_appli(IN name) FROM public;

COMMENT ON FUNCTION public.revoke_appli(IN name) IS
'Revoke a postgresql role to access OPM API';


/* v2.1
public.grant_dispatcher(wh, role)

@return rc: state of the operation
 */
CREATE OR REPLACE
FUNCTION public.grant_dispatcher(IN p_whname name, IN p_rolname name,
    OUT rc boolean)
LANGUAGE plpgsql VOLATILE STRICT LEAKPROOF
SET search_path TO public
AS $$
BEGIN
    IF NOT public.wh_exists(p_whname) THEN
        RAISE EXCEPTION 'Warehouse ''%'' does not exists!', p_whname;
    END IF;

    EXECUTE pg_catalog.format('SELECT %I.grant_dispatcher($1)', p_whname)
        INTO STRICT rc USING p_rolname;

    RETURN;
END
$$;

REVOKE ALL ON FUNCTION public.grant_dispatcher(IN name, IN name, OUT boolean) FROM public;

COMMENT ON FUNCTION public.grant_dispatcher(IN name, IN name, OUT boolean)
IS 'Grant a role to dispatch performance data in a warehouse hub table.

Must be admin.';



/* v2.1
public.revoke_dispatcher(wh, role)

@return rc: state of the operation
 */
CREATE OR REPLACE
FUNCTION public.revoke_dispatcher(IN p_whname name, IN p_rolname name,
    OUT rc boolean)
LANGUAGE plpgsql VOLATILE STRICT LEAKPROOF
SET search_path TO public
AS $$
BEGIN
    IF NOT public.wh_exists(p_whname) THEN
        RAISE EXCEPTION 'Warehouse ''%'' does not exists!', p_whname;
        RETURN;
    END IF;


    EXECUTE pg_catalog.format('SELECT %I.revoke_dispatcher($1)', p_whname)
        INTO STRICT rc USING p_rolname;

    RETURN;
END
$$;

REVOKE ALL ON FUNCTION public.revoke_dispatcher(IN name, IN name, OUT boolean) FROM public;

COMMENT ON FUNCTION public.revoke_dispatcher(IN name, IN name, OUT boolean) IS
'Revoke dispatch ability for a give role on a given hub table.';





/*********** SESSION *************/

/* v2.1
public.session_role()

Returns the current session role.
*/
CREATE OR REPLACE
FUNCTION public.session_role (OUT rolename text)
LANGUAGE SQL VOLATILE LEAKPROOF SECURITY INVOKER
SET search_path TO pg_catalog
AS $$
    SELECT pg_catalog.current_setting('opm.rolname')::text;
$$;

REVOKE ALL ON FUNCTION public.session_role() FROM public;

COMMENT ON FUNCTION public.session_role() IS
'return the current OPM session role';

SELECT * FROM public.register_api('public.session_role()');

/*********** ACCOUNT *************/

/* v2.1
public.create_account
Create a new account.

Can only be executed by admins.

@return id: id of the new account.
@return name: name of the new account.
*/
CREATE OR REPLACE
FUNCTION public.create_account (IN p_account text,
    OUT id bigint, OUT accname text)
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'You must be an admin.';
    END IF;

    INSERT INTO public.roles (rolname)
    VALUES (p_account)
    RETURNING roles.id, roles.rolname
        INTO create_account.id, create_account.accname;

    RETURN;
END 
$$;

REVOKE ALL ON FUNCTION public.create_account(IN text, OUT bigint, OUT text)
    FROM public;

COMMENT ON FUNCTION public.create_account (IN text, OUT bigint, OUT text) IS 'Create a new OPM account.

It creates a role with no login/pass in table public.roles.

@return id: id of the new account.
@return name: name of the new account.';

SELECT * FROM public.register_api('public.create_account(text)');

/* v2.1
public.drop_account

Drop an account. It can not be opm_admins.

Also drop all roles that are connected *only* to this particular account.

@return id: oid of the dropped roles
@return rolname: name of the dropped roles
*/
CREATE OR REPLACE
FUNCTION public.drop_account(IN p_account text)
RETURNS TABLE (id bigint, rolname text)
LANGUAGE plpgsql VOLATILE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'You must be an admin.';
    END IF;

    IF p_account = 'opm_admins' THEN
        RAISE EXCEPTION 'Account opm_admins can not be deleted!';
    END IF;

    RETURN QUERY WITH role_list AS (
        SELECT m.rolname
        FROM public.members AS m
        WHERE m.rolname IN (
            SELECT _m.rolname
            FROM public.members AS _m
            WHERE _m.member = p_account
        )
        GROUP BY 1
        HAVING pg_catalog.count(1) = 1
    )
    DELETE FROM public.roles AS r
    USING role_list AS d
    WHERE (r.rolname = p_account AND NOT r.canlogin) -- drop the account
            OR (r.rolname = d.rolname AND r.canlogin) -- drop all user with ONLY this account
    RETURNING r.id, r.rolname;
END
$$;


REVOKE ALL ON FUNCTION public.drop_account (IN text)
    FROM public;

COMMENT ON FUNCTION public.drop_account(IN text) IS '
Drop an account.

It drops the account and also OPM roles that are only in this account.

@return id: oid of the dropped roles
@return rolname: name of the dropped roles';

SELECT * FROM public.register_api('public.drop_account(text)');

/* v2.1
public.list_accounts()
*/
CREATE OR REPLACE
FUNCTION public.list_accounts()
RETURNS TABLE (accid bigint, accname text)
LANGUAGE plpgsql STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        RETURN QUERY SELECT id, rolname
            FROM public.roles
            WHERE NOT canlogin;
    ELSE
        RETURN QUERY SELECT id, rolname
            FROM public.roles
            WHERE NOT canlogin
                AND public.is_member(rolname);
    END IF;
END
$$;

REVOKE ALL ON FUNCTION public.list_accounts() FROM public;

COMMENT ON FUNCTION public.list_accounts() IS 'List OPM accounts.

If current user is member of opm_admins, list all account on the system.

If current user is not admin, list all account who are related to the current user.';

SELECT * FROM public.register_api('public.list_accounts()');

/* v2.1
is_account(rolname)

@return rc: true if the given rolname is an account
 */
CREATE OR REPLACE
FUNCTION public.is_account(IN p_rolname text,
   OUT rc boolean)
LANGUAGE plpgsql STRICT STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        SELECT pg_catalog.count(1) > 0 INTO rc
        FROM public.roles
        WHERE rolname = p_rolname
            AND NOT canlogin;
    ELSE
        SELECT pg_catalog.count(1) > 0 INTO rc
        FROM public.roles
        WHERE rolname = p_rolname
            AND NOT canlogin
            AND public.is_member(rolname);
    END IF;

    RETURN;
END
$$;

REVOKE ALL ON FUNCTION public.is_account(IN text, OUT boolean) FROM public;

COMMENT ON FUNCTION public.is_account(IN text, OUT boolean)
IS 'Tells if the given rolname is an OPM account.

Only check if current user is member of given role';

SELECT * FROM public.register_api('public.is_account(text)');

/*********** USERS *************/


/*
authenticate (p_user, p_passwd)

Authenticate given user/password credential against the public.role table.
*/
CREATE OR REPLACE
FUNCTION public.authenticate (IN p_user text, IN p_passwd text,
    OUT authenticated boolean)
LANGUAGE SQL STABLE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
    SELECT coalesce(pg_catalog.bool_and(password = p_passwd), 'f'::boolean)
    FROM public.roles
    WHERE rolname = p_user;
$$;

REVOKE ALL ON FUNCTION public.authenticate(IN text, IN text, OUT boolean) FROM public;

COMMENT ON FUNCTION public.authenticate(IN text, IN text, OUT boolean)
IS 'Check if given user/password credential is a valid OPM role';

SELECT * FROM public.register_api('public.authenticate(text,text)');

/*
set_opm_session(p_user)

Set the current OPM role for the session.
*/
CREATE OR REPLACE FUNCTION public.set_opm_session(p_user text,
    OUT opm_session text)
RETURNS text
LANGUAGE SQL STABLE STRICT SECURITY DEFINER
SET search_path TO public
AS $$
    SELECT pg_catalog.set_config('opm.rolname', p_user, false);
$$;

REVOKE ALL ON FUNCTION public.set_opm_session(IN text, OUT text) FROM public;

COMMENT ON FUNCTION public.set_opm_session(IN text)
IS 'Set the current OPM role for the session.

This OPM-session role define what the user can see/access through the API';

SELECT * FROM public.register_api('public.set_opm_session(text)');

/* v2.1
public.create_user
Create a new OPM role in an OPM account.

This function creates a role in the public.roles table with given password
and member of given account(s).

The p_accounts MUST have at least one account. We don't want user with no
accounts.

Can only be executed by admins.

@return id: id of the new account.
@return name: name of the new account.
*/
CREATE OR REPLACE
FUNCTION public.create_user (IN p_user text, IN p_passwd text, IN p_accounts text[],
    OUT id bigint, OUT usename text)
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    p_account name;
BEGIN

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'You must be an admin.';
    END IF;

    IF coalesce(pg_catalog.array_length(p_accounts, 1), 0) < 1 THEN
        RAISE EXCEPTION 'A user must have at least one associated account!';
    END IF;

    INSERT INTO public.roles (rolname, canlogin, password)
    VALUES (p_user, 't', pg_catalog.md5(p_passwd||p_user))
    RETURNING roles.id, roles.rolname INTO create_user.id, create_user.usename;

    FOREACH p_account IN ARRAY p_accounts
    LOOP
        -- FIXME: test with unknown account
        PERFORM public.grant_account(p_user, p_account);
    END LOOP;

EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Given user already exists: ''%''', p_user;
END
$$;

REVOKE ALL ON FUNCTION public.create_user(IN text, IN text, IN text[], OUT bigint, OUT text)
    FROM public;

COMMENT ON FUNCTION public.create_user(IN p_user text, IN p_passwd text, IN p_accounts text[],
                                        OUT rc boolean) IS
'Create a new OPM user in some OPM accounts.

It creates the given user in the public.roles table.

The p_accounts MUST have at least one account. We don''t want user with no
accounts.

@return id: id of the new account.
@return name: name of the new account.';

SELECT * FROM public.register_api('public.create_user(text,text,text[])');

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
    END IF

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

SELECT * FROM public.register_api('public.drop_user(text)');


/* v2.1
public.update_user
Change the password of an opm user.

Can only be executed by roles opm and opm_admins.

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
    IF NOT public.is_admin() THEN
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

Must be admin.' ;

SELECT * FROM public.register_api('public.update_user(text,text)');


/* v2.1 */
CREATE OR REPLACE
FUNCTION public.update_current_user(text)
RETURNS boolean
LANGUAGE SQL STRICT LEAKPROOF VOLATILE
SET search_path TO public
AS $$
    SELECT public.update_user(public.session_role(), $1);
$$;

REVOKE ALL ON FUNCTION public.update_current_user(text)
    FROM public ;

COMMENT ON FUNCTION public.update_current_user(text) IS
'Change the password of the current opm user.' ;

SELECT * FROM public.register_api('public.update_current_user(text)');


/* v2.1
public.list_users()

Return the id, role name and account of all users if OPM session role is admin.
If the user is not admin, returns the list of users from the same accounts

@return useid:   the user id
@return accname: the account name
@return rolname: the user name
*/
CREATE OR REPLACE
FUNCTION public.list_users()
RETURNS TABLE (useid bigint, accname text, rolname text)
LANGUAGE plpgsql STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        RETURN QUERY SELECT r.id, m.member, r.rolname
            FROM public.roles AS r
                JOIN public.members AS m ON (r.rolname=m.rolname)
            WHERE r.canlogin;
    ELSE
        RETURN QUERY SELECT r.id, m.member, r.rolname
            FROM public.roles AS r
                JOIN public.members AS m ON (r.rolname=m.rolname)
            WHERE r.canlogin
                AND public.is_member(m.member);
    END IF;
END
$$;

REVOKE ALL ON FUNCTION public.list_users() FROM public;

COMMENT ON FUNCTION public.list_users() IS 'List OPM users.

If current user is admin, list all users / account on the system.

If current user is not admin, list all users and account who are related to the current user.';

SELECT * FROM public.register_api('public.list_users()');



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
                AND r.rolname = p_accname;
    ELSE
        RETURN QUERY SELECT r.id, m.member, r.rolname
            FROM public.roles AS r
                JOIN public.members AS m ON (r.rolname=m.rolname)
            WHERE r.canlogin
                AND r.rolname = p_accname
                AND public.is_member(m.member);
    END IF;
END
$$;

REVOKE ALL ON FUNCTION public.list_users(text) FROM public;

COMMENT ON FUNCTION public.list_users(text) IS 'List OPM users.

If current user is admin, list all users from the given account.

If current user is not admin, list all users from given account if the user is member of this account.';

SELECT * FROM public.register_api('public.list_users(text)');


/* v2.1
is_user(rolname)

@return rc: true if the given rolname is a simple user
 */
CREATE OR REPLACE
FUNCTION public.is_user(IN p_rolname text,
    OUT rc boolean)
LANGUAGE plpgsql STRICT STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        SELECT pg_catalog.count(1) > 0 INTO rc
        FROM public.roles AS r
        WHERE r.canlogin
            AND r.rolname = p_rolname;
    ELSE
        SELECT pg_catalog.count(1) > 0 INTO rc
        FROM public.roles AS r
            JOIN public.members AS m ON (r.rolname=m.rolname)
        WHERE r.canlogin
            AND r.rolname = p_rolname
            AND public.is_member(m.member);
    END IF;

    RETURN;
END
$$;

REVOKE ALL ON FUNCTION public.is_user(IN text, OUT boolean) FROM public;

COMMENT ON FUNCTION public.is_user(IN text, OUT boolean)
IS 'Tells if the given rolname is a valid OPM user.';

SELECT * FROM public.register_api('public.is_user(text)');


/*********** MEMBERSHIP *************/

/* v2.1
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
LANGUAGE plpgsql STABLE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
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

    RETURN;
END
$$;

REVOKE ALL ON FUNCTION public.is_member(IN p_rolname text, IN p_accname text, OUT rc boolean) FROM public;

COMMENT ON FUNCTION public.is_member(IN p_rolname text, IN p_accname text, OUT rc boolean) IS
'Tells if the given OPM role is member of given an OPM account.


A non admin user can only check if given rolname is member of one
of his own account.';

SELECT * FROM public.register_api('public.is_member(text,text)');


/* v2.1
is_member(accname)

Check if current session user is member of given account.

@return rc: true if current OPM session role is member of accname
*/
CREATE OR REPLACE
FUNCTION public.is_member(IN p_accname text, OUT rc boolean)
LANGUAGE SQL STABLE STRICT LEAKPROOF SECURITY DEFINER
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

SELECT * FROM public.register_api('public.is_member(text)');


/* v2.1
is_member(id_account)

Check if current session user is member of given account (by id).

@return rc: true if current OPM session role is member of accname
*/
CREATE OR REPLACE
FUNCTION public.is_member(IN p_id_account bigint, OUT rc boolean)
LANGUAGE SQL STABLE STRICT LEAKPROOF SECURITY DEFINER
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

SELECT * FROM public.register_api('public.is_member(bigint)');



/* v2.1
is_admin(rolname)

@return rc: true if the given rolname is an admin
 */
CREATE OR REPLACE
FUNCTION public.is_admin(IN p_rolname text, OUT rc boolean)
LANGUAGE SQL STRICT STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
    SELECT pg_catalog.count(1) = 1
    FROM public.members AS m
    WHERE m.rolname = p_rolname
        AND m.member = 'opm_admins';
$$;

REVOKE ALL ON FUNCTION public.is_admin(IN text, OUT boolean) FROM public;

COMMENT ON FUNCTION public.is_admin(IN text, OUT boolean) IS
'Tells if the given OPM session role is an OPM admin.';

SELECT * FROM public.register_api('public.is_admin(text)');


/* v2.1
is_admin()

@return rc: true if the current session rolname is an admin
            NULL if role does not exist

 */
CREATE OR REPLACE
FUNCTION public.is_admin(OUT rc boolean)
LANGUAGE SQL STRICT STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
    SELECT pg_catalog.count(1) = 1
    FROM public.members AS m
    WHERE m.rolname = public.session_role()
        AND m.member = 'opm_admins';
$$;

REVOKE ALL ON FUNCTION public.is_admin(OUT boolean) FROM public;

COMMENT ON FUNCTION public.is_admin(OUT boolean) IS
'Tells if the current OPM session role is an OPM admin.';

SELECT * FROM public.register_api('public.is_admin()');


/* v2.1
grant_account(p_rolname name, p_accountname name)

Only admins can grant an account.

@return : true if granted or user already in this account
 */
CREATE OR REPLACE
FUNCTION public.grant_account(IN p_rolname text, IN p_accountname text,
    OUT granted boolean)
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'You must be an admin!';
    END IF;

    IF public.is_member(p_rolname, p_accountname) THEN
        grant_account.granted := true;
        RETURN;
    END IF;

    -- Will break FK if one or both side do not exist
    INSERT INTO members
    VALUES (p_rolname, p_accountname)
    RETURNING true INTO grant_account.granted;
END
$$;

REVOKE ALL ON FUNCTION public.grant_account(IN text, IN text, OUT boolean) FROM public;

COMMENT ON FUNCTION public.grant_account(p_rolname text, p_accountname text) IS 'Grant an OPM account to an OPM user.';

SELECT * FROM public.register_api('public.grant_account(text,text)');


/* v2.1
revoke_account(p_rolname text, p_accountname text)

@return : true if revoked
          false in other situation (not member, ...)

 */
CREATE OR REPLACE
FUNCTION public.revoke_account(p_rolname text, p_accountname text)
RETURNS boolean
LANGUAGE plpgsql VOLATILE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_ok boolean;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'You must be an admin!';
    END IF;

    -- check if both exists
    SELECT pg_catalog.count(1) = 2 INTO v_ok
    FROM public.roles AS r
    WHERE (r.rolname = p_rolname AND r.canlogin)
        OR (r.rolname = p_accountname AND NOT r.canlogin);

    IF NOT v_ok THEN
        RAISE EXCEPTION 'One or both given roles does not exist.';
    END IF;

    -- checking membership
    IF NOT public.is_member(p_rolname, p_accountname) THEN
        RETURN false;
    END IF;

    -- We can not revoke an accouant from a user if it is his last one
    SELECT pg_catalog.count(1) > 0 INTO v_ok
    FROM public.members AS m
    WHERE m.rolname = p_rolname
        AND m.member <> p_accountname;

    IF NOT v_ok THEN
        RAISE EXCEPTION 'Could not revoke account % from user % : user must have at least one account', p_accountname, p_rolname;
    END IF;

    DELETE FROM members
    WHERE rolname = p_rolname 
        AND member = p_accountname
    RETURNING true INTO v_ok;

    RETURN v_ok;
END
$$;

REVOKE ALL ON FUNCTION public.revoke_account(p_rolname text, p_accountname text) FROM public;

COMMENT ON FUNCTION public.revoke_account(p_rolname text, p_accountname text) IS
'Revoke an account from a role.

Note that you can not revoke a user from an account if this is the only existing one.';

SELECT * FROM public.register_api('public.revoke_account(text,text)');


/*********** WAREHOUSES *************/


/* v2.1
list_warehouses()

@return whname: names of the warehouses
 */
CREATE OR REPLACE
FUNCTION public.list_warehouses()
RETURNS TABLE (whname name)
LANGUAGE SQL STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
    SELECT n.nspname
    FROM pg_catalog.pg_namespace n
    JOIN pg_catalog.pg_available_extensions e
        ON (n.nspname = e.name AND e.installed_version IS NOT NULL)
    WHERE nspname ~ '^wh_';
$$;

REVOKE ALL ON FUNCTION public.list_warehouses() FROM public;

COMMENT ON FUNCTION public.list_warehouses() IS
'List all warehouses.';

SELECT * FROM public.register_api('public.list_warehouses()');


/* v2.1
wh_exists(wh)

@return rc: true if the given warehouse exists
 */
CREATE OR REPLACE
FUNCTION public.wh_exists(IN p_whname text,
    OUT rc boolean)
LANGUAGE SQL STABLE LEAKPROOF STRICT
SET search_path TO public
AS $$
    SELECT pg_catalog.count(1) > 0
    FROM public.list_warehouses() AS w
    WHERE w.whname = p_whname;
$$;

REVOKE ALL ON FUNCTION public.wh_exists(IN text, OUT boolean) FROM public;

COMMENT ON FUNCTION public.wh_exists(IN text, OUT boolean) IS
'Returns true if the given warehouse exists.';

SELECT * FROM public.register_api('public.wh_exists(text)');


/*********** SERVERS *************/


/* v2.1
list_servers()

@return id: Server id
@return name: Server name
@return rolname: Server owner
*/
CREATE OR REPLACE
FUNCTION public.list_servers()
RETURNS TABLE (id bigint, hostname text, rolname text)
LANGUAGE plpgsql STABLE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        RETURN QUERY SELECT s.id, s.hostname, r.rolname
            FROM public.servers s
                LEFT JOIN public.roles r ON s.id_role = r.id;
    ELSE
        RETURN QUERY SELECT s.id, s.hostname, r.rolname
            FROM public.servers s
                JOIN public.roles r ON s.id_role = r.id
            WHERE public.is_member(r.rolname);
    END IF;
END
$$;

REVOKE ALL ON FUNCTION public.list_servers() FROM public;

COMMENT ON FUNCTION public.list_servers() IS
'List servers available for the session user.';

SELECT * FROM public.register_api('public.list_servers()');

/* v2.1
public.get_server(id)

Returns data about given server by id

@return public.servers%TABLE
*/
CREATE OR REPLACE
FUNCTION public.get_server(IN p_id bigint,
    OUT server public.servers)
LANGUAGE plpgsql STABLE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        SELECT * INTO server
            FROM public.servers s
            WHERE s.id = p_id;
    ELSE
        SELECT * INTO server
        FROM public.servers s
            JOIN public.roles r ON s.id_role = r.id
        WHERE public.is_member(r.rolname)
            AND s.id = p_id;
    END IF;

    RETURN;
END
$$;

REVOKE ALL ON FUNCTION public.get_server(bigint) FROM public;

COMMENT ON FUNCTION public.get_server(bigint) IS
'Returns all data about given server by id.';

SELECT * FROM public.register_api('public.get_server(bigint)');


/* v2.1
grant_server(server_id, accname)

Set given account as owner of the given server id.

Must be admin.
 */
CREATE OR REPLACE
FUNCTION public.grant_server(IN p_server_id bigint, IN p_rolname text,
    OUT rc boolean)
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_idserv  BIGINT := NULL;
    v_idowner BIGINT := NULL;
BEGIN
    rc := NULL;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'You must be an admin!';
    END IF;

    -- Does the role exists ?
    IF NOT public.is_account(p_rolname) THEN
        RAISE EXCEPTION 'Given role is not an account.';
    END IF;

    -- Does the server exists ?
    SELECT s.id, s.id_role INTO v_idserv, v_idowner
    FROM public.servers AS s
    WHERE s.id = p_server_id;

    IF v_idserv IS NULL THEN
        RAISE EXCEPTION 'This server does not exists.';
    END IF;

    -- Is the server already owned ?
    IF v_idowner IS NOT NULL THEN
        RAISE EXCEPTION 'This server is already owned by another role.';
    END IF;

    UPDATE public.servers
    SET id_role = r.id
    FROM public.roles AS r
    WHERE servers.id = p_server_id
        AND r.rolname = p_rolname;

    rc := true;
END
$$;

REVOKE ALL ON FUNCTION public.grant_server(IN p_server_id bigint, IN p_rolname text, OUT rc boolean) FROM public;

COMMENT ON FUNCTION public.grant_server(IN p_server_id bigint, IN p_rolname text, OUT rc boolean) IS
'Set given account as owner of the given server id.

Must be admin.';

SELECT * FROM public.register_api('public.grant_server(bigint,text)');

/* v2.1
revoke_server(server_id, accname)

Revoke given account as owner of the given server id.

Must be admin
 */
CREATE OR REPLACE
FUNCTION public.revoke_server(IN p_server_id bigint, IN p_rolname text,
    OUT rc boolean)
LANGUAGE plpgsql VOLATILE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_idserv  bigint := NULL;
    v_owner   text := NULL;
BEGIN
    rc := NULL;

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'You must be an admin!';
    END IF;

    rc := false;

    UPDATE public.servers AS s
    SET id_role = NULL
    FROM public.roles AS r
    WHERE r.id = s.id_role
        AND s.id = p_server_id
        AND r.rolname = p_rolname;

    -- Does the account own this server ?
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Server or account does not exists or the account is not the owner.';
    END IF;

    rc := true;
END
$$;

REVOKE ALL ON FUNCTION public.revoke_server(IN p_server_id bigint, IN p_rolname text, OUT rc boolean) FROM public;

COMMENT ON FUNCTION public.revoke_server(IN p_server_id bigint, IN p_rolname text, OUT rc boolean) IS
'Revoke given account as owner of the given server id.

Must be admin';

SELECT * FROM public.register_api('public.revoke_server(bigint,text)');


/*********** SERVICES *************/


/* v2.1
list_services()

List services available for the session user
 */
CREATE OR REPLACE
FUNCTION public.list_services()
RETURNS TABLE (id bigint, id_server bigint, warehouse text,
               service text, last_modified date,
               creation_ts timestamp with time zone, servalid interval)
LANGUAGE plpgsql STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        RETURN QUERY SELECT ser.id, ser.id_server, ser.warehouse, ser.service,
                ser.last_modified, ser.creation_ts, ser.servalid
            FROM public.services ser;
    ELSE
        RETURN QUERY SELECT ser.id, ser.id_server, ser.warehouse, ser.service,
                ser.last_modified, ser.creation_ts, ser.servalid
            FROM public.list_servers() AS srv
                JOIN public.services ser
                    ON srv.id = ser.id_server;
    END IF;
END $$;

REVOKE ALL ON FUNCTION public.list_services() FROM public;

COMMENT ON FUNCTION public.list_services() IS
'List services available for the session user.';

SELECT * FROM public.register_api('public.list_services()');


/*********** METRICS *************/


/* v2.1
public.list_metrics(bigint)

Return every metrics used in given graphs (by id) if current user is allowed to.
*/
CREATE OR REPLACE
FUNCTION public.list_metrics(p_id_graph bigint)
RETURNS TABLE (id_graph bigint, id_metric bigint, label text, unit text,
    id_service bigint, available boolean)
LANGUAGE plpgsql STRICT STABLE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF public.is_admin() THEN
        RETURN QUERY
            SELECT ss.id_graph, m.id, m.label, m.unit, m.id_service,
                s.id_graph IS NOT NULL AS available
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
                s.id_graph IS NOT NULL AS available
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
'Return every metrics used in given graphs (by id) if current user is allowed to..';

SELECT * FROM public.register_api('public.list_metrics(bigint)');



/* v2.1
public.update_graph_metrics(p_id_graph bigint, p_id_metrics bigint[])
Update what are the metrics associated to the given graph.

@param p_id_metrics: array of all metrics showed in the graph.

Returns 2 arrays:
  * added bigint[]: Array of added metrics
  * removed bigint[]: Array of removed metrics
*/
CREATE OR REPLACE
FUNCTION public.update_graph_metrics( p_id_graph bigint, p_id_metrics bigint[],
    OUT added bigint[], OUT removed bigint[])
LANGUAGE plpgsql STRICT VOLATILE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_result  record;
    v_remove  bigint[];
    v_add     bigint[];
BEGIN
    IF NOT public.is_admin() THEN
        SELECT 1
        FROM public.list_graphs() AS g
        WHERE g.id = p_id_graph;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Graph id does not exists or not granted.';
        END IF;
    END IF;

    FOR v_result IN
        SELECT gs.id_metric AS to_remove, a.id_metric AS to_add
        FROM (
            SELECT _s.id_metric
            FROM public.series AS _s
            WHERE _s.id_graph = p_id_graph
        ) AS gs
        FULL JOIN (
            SELECT * FROM pg_catalog.unnest ( p_id_metrics )
        ) AS a(id_metric) ON a.id_metric = gs.id_metric
        WHERE gs.id_metric IS NULL OR a.id_metric IS NULL
    LOOP
        /* if "existing" is NULL, the metric should be added to the graph
         * else "given" is NULL, the metric should be removed from the
         * graph
         */
        IF v_result.to_add IS NOT NULL THEN
            v_add := pg_catalog.array_append(v_add, v_result.to_add);
        ELSE
            v_remove := pg_catalog.array_append(v_remove, v_result.to_remove);
        END IF;
    END LOOP;

    -- Add new metrics to the graph
    INSERT INTO public.series (id_graph, id_metric)
    SELECT p_id_graph, pg_catalog.unnest(v_add);

    -- Remove metrics from the graph
    PERFORM 1 FROM public.graphs AS g
    WHERE g.id = p_id_graph FOR UPDATE;

    FOR v_result IN SELECT pg_catalog.array_agg(id_metric) AS vals, to_delete
        FROM (
                SELECT _s.id_metric, pg_catalog.count(1) > 1 AS to_delete
                FROM public.series AS _s
                WHERE _s.id_metric = ANY ( v_remove )
                GROUP BY _s.id_metric
        ) AS sub
        GROUP BY to_delete
    LOOP
        IF v_result.to_delete THEN
            DELETE FROM public.series
            WHERE id_metric = ANY ( v_result.vals )
                AND id_graph = p_id_graph;
        ELSE
            UPDATE public.series SET id_graph = NULL
            WHERE id_metric = ANY ( v_result.vals )
                AND id_graph = p_id_graph;
        END IF;
    END LOOP;

    added := v_add; removed := v_remove;
END
$$;

REVOKE ALL ON FUNCTION public.update_graph_metrics(bigint, bigint[]) FROM public ;

COMMENT ON FUNCTION public.update_graph_metrics(bigint, bigint[]) IS
'Update what are the metrics associated to the given graph.' ;

SELECT * FROM public.register_api('public.update_graph_metrics(bigint,bigint[])');


/*********** GRAPHS *************/


/* v2.1
public.list_graphs()

Return every graphs user can see, including relations with
services and servers related informations.
*/
CREATE OR REPLACE
FUNCTION public.list_graphs()
RETURNS TABLE (id bigint, graph text, description text, config json,
               id_server bigint, id_service bigint, warehouse text)
LANGUAGE plpgsql STABLE STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    -- FIXME DISTINCT ?!
    IF public.is_admin() THEN
        RETURN QUERY SELECT DISTINCT ON (g.id) g.id, g.graph,
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
                    ON s2.id_server = s3.id;
    ELSE
        RETURN QUERY SELECT DISTINCT ON (g.id) g.id, g.graph,
                g.description, g.config,
                s3.id, s2.id, s2.warehouse
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

SELECT * FROM public.register_api('public.list_graphs()');


/* v2.1
public.create_graph_for_new_metric(p_id_server bigint) returns boolean
@return rc: status

It automatically generates all graphs for new metrics for a specified
server. If called multiple times, it will only generate
"missing" graphs. A graph will be considered as missing if a metric is not
present in any graph. Therefore, it's currently impossible not to graph a metric.
FIXME: fix this limitation.
*/
CREATE OR REPLACE
FUNCTION public.create_graph_for_new_metric(IN p_server_id bigint,
    OUT rc boolean)
LANGUAGE plpgsql STRICT LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_owner   bigint;
  metricsrow record;
BEGIN

    rc := false;

    --Does the server exists ?
    SELECT id_role INTO v_owner
    FROM public.servers AS s
    WHERE s.id = p_server_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Server unknown or not allowed for current user.';
    END IF;

  -- Is the user allowed to create graphs ?
    IF public.is_member(v_owner) THEN
        RAISE EXCEPTION 'Server unknown or not allowed for current user.';
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
            SELECT 1
            FROM public.series AS gs
                JOIN wh_nagios.metrics m2 ON m2.id = gs.id_metric
            WHERE m2.id = m.id
        );
  END LOOP;
  rc := true;
END
$$;

REVOKE ALL ON FUNCTION public.create_graph_for_new_metric(p_server_id bigint, OUT rc boolean) FROM public;

COMMENT ON FUNCTION public.create_graph_for_new_metric(p_server_id bigint, OUT rc boolean) IS
'Create default graphs for all new services.';

SELECT * FROM public.register_api('public.create_graph_for_new_metric(bigint)');


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
BEGIN
    -- IS user allowed to see graph ?
    PERFORM 1
    FROM public.list_graphs() as g
    WHERE g.id = p_id_graph ;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Graph not found or not allowed.';
    END IF;

    WITH ins_graph AS (
        INSERT INTO public.graphs (graph, description, config)
        SELECT 'Clone - ' || g.graph, g.description, g.config
        FROM public.graphs AS g
        WHERE g.id = p_id_graph
        RETURNING graphs.id
    ),
    ins_ser AS (
        INSERT INTO public.series
        SELECT ng.id, s.id_metric
        FROM public.series AS s, ins_graph AS ng
        WHERE s.id_graph = p_id_graph
        RETURNING series.id_graph
    )
    SELECT ns.id_graph INTO v_new_id
    FROM ins_ser AS ns
    LIMIT 1;

    RETURN v_new_id;
END
$$;

REVOKE ALL ON FUNCTION public.clone_graph(bigint) FROM public;

COMMENT ON FUNCTION public.clone_graph(bigint) IS 'Clone given graph by id.

@return: id of the new graph.';

SELECT * FROM public.register_api('public.clone_graph(bigint)');


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
        WHERE graphs.id = g.id
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

SELECT * FROM public.register_api('public.delete_graph(bigint)');


/* v2.1
public.edit_graph(id, graph_title, description, config)

Edit given graph by id.

@return : true on success
*/
CREATE OR REPLACE
FUNCTION public.edit_graph(IN p_id bigint, IN p_graph text, IN p_description text, IN p_config json,
    OUT rc boolean)
LANGUAGE plpgsql VOLATILE LEAKPROOF SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'You must be an admin!';
    END IF;

    UPDATE public.graphs
    SET graph = p_graph, description = p_description, config = p_config
    WHERE id = p_id
    RETURNING true INTO rc;

    RETURN;
END
$$;

REVOKE ALL ON FUNCTION public.edit_graph(bigint, text, text, json) FROM public;

COMMENT ON FUNCTION public.edit_graph(bigint, text, text, json) IS
'Edit given graph by id.

Return true on success';

SELECT * FROM public.register_api('public.edit_graph(bigint, text, text, json)');

/*********** SERIES *************/



/* v2.1
public.get_sampled_metric_data(bigintn timestamptz, timestamptz, integer)
Sample a metric data to get the specified number of values.
@id : unique identifier of graph to delete.
@return : set of metric_value (empty on error or not granted)

FIXME: return colname shouldn't use reserved word "value"
*/
CREATE OR REPLACE
FUNCTION public.get_sampled_metric_data(p_id_metric bigint, p_timet_begin timestamp with time zone, p_timet_end timestamp with time zone, p_sample_num integer)
RETURNS TABLE(value metric_value)
LANGUAGE plpgsql STABLE LEAKPROOF STRICT SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_warehouse text := NULL;
    v_sec integer ;
BEGIN
    IF p_sample_num < 1 THEN
        RETURN;
    END IF;

    IF public.is_admin() THEN
        SELECT warehouse INTO v_warehouse
        FROM public.services s
            JOIN public.metrics m ON s.id = m.id_service
        WHERE m.id = p_id_metric ;
    ELSE
        SELECT warehouse INTO v_warehouse
        FROM public.list_services() AS s
            JOIN public.metrics m ON s.id = m.id_service
        WHERE m.id = p_id_metric ;
    END IF;

    IF NOT FOUND THEN
        RETURN;
    END IF ;

    v_sec := ceil( ( extract(epoch FROM p_timet_end) - extract(epoch FROM p_timet_begin) ) / p_sample_num ) ;

    RETURN QUERY EXECUTE format('
        SELECT min(timet), max(value)
        FROM (SELECT * FROM %I.get_metric_data($1, $2, $3)) tmp
        GROUP BY (extract(epoch from timet)::float8/$4)::bigint*$4
        ORDER BY 1', v_warehouse
    ) USING p_id_metric, p_timet_begin, p_timet_end, v_sec ;
END;
$$;

REVOKE ALL ON FUNCTION public.get_sampled_metric_data(bigint, timestamp with time zone, timestamp with time zone, integer) FROM public;

COMMENT ON FUNCTION public.get_sampled_metric_data(bigint, timestamp with time zone, timestamp with time zone, integer) IS
'Return sampled metric data for the specified metric with the specified number of samples.
Result set is empty if not found or not granted.';

SELECT * FROM public.register_api('public.get_sampled_metric_data(bigint,timestamp with time zone,timestamp with time zone,integer)');


/* v2.1
js_time: Convert the input date to ms (UTC), suitable for javascript
*/
CREATE OR REPLACE
FUNCTION public.js_time(timestamptz)
RETURNS bigint
LANGUAGE SQL STRICT LEAKPROOF IMMUTABLE
AS $$
    SELECT (extract(epoch FROM $1)*1000)::bigint;
$$;

REVOKE ALL ON FUNCTION public.js_time(timestamptz) FROM public;

COMMENT ON FUNCTION public.js_time(timestamptz) IS
'Return a timestamp without time zone formatted for javascript use.' ;

SELECT * FROM public.register_api('public.js_time(timestamptz)');


/* v2.1
js_timetz: Convert the input date to ms (with timezone), suitable for javascript
*/
CREATE OR REPLACE
FUNCTION public.js_timetz(timestamptz)
RETURNS bigint
LANGUAGE SQL STRICT LEAKPROOF IMMUTABLE
AS $$
    SELECT ((extract(epoch FROM $1) + extract(timezone FROM $1))*1000)::bigint;
$$;

REVOKE ALL ON FUNCTION public.js_timetz(timestamptz) FROM public;

COMMENT ON FUNCTION public.js_timetz(timestamptz) IS
'Return a timestamp with time zone formatted for javascript use.';

SELECT * FROM public.register_api('public.js_timetz(timestamptz)');


SELECT * FROM public.set_extension_owner('opm_core');
