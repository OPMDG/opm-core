-- This program is open source, licensed under the PostgreSQL License.
-- For license terms, see the LICENSE file.
--
-- Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

\unset ECHO
\i t/setup.sql

SELECT plan(224);

SELECT diag(E'\n==== Install opm-core ====\n');

SELECT has_schema('public', 'Schema public exists.' );

SELECT lives_ok(
    $$CREATE EXTENSION opm_core$$,
    'Create extension "opm_core"'
);

SELECT has_extension('opm_core', 'Extension "opm_core" is installed.');

SELECT has_table('public', 'roles', 'Schema public contains table "roles" of opm_core.' );
SELECT has_table('public', 'members', 'Schema public contains table "members" of opm_core.' );
SELECT has_table('public', 'servers', 'Schema public contains table "servers" of opm_core.' );
SELECT has_table('public', 'services', 'Schema public contains table "services" of opm_core.' );
SELECT has_table('public', 'metrics', 'Schema public contains table "metrics" of opm_core.' );
SELECT has_table('public', 'graphs', 'Schema public contains table "graphs" of opm_core.' );
SELECT has_table('public', 'series', 'Schema public contains table "series" of opm_core.' );



SELECT has_function('public', 'set_extension_owner', '{name}', 'Function "set_extension_owner" exists.');
SELECT has_function('public', 'create_admin', '{name, text}', 'Function "create_admin" exists.');
SELECT has_function('public', 'grant_dispatcher', '{name,name}', 'Function "grant_dispatcher" exists.');
SELECT has_function('public', 'revoke_dispatcher', '{name,name}', 'Function "revoke_dispatcher" exists.');
SELECT has_function('public', 'grant_appli', '{name}', 'Function "grant_appli" exists.');
SELECT has_function('public', 'revoke_appli', '{name}', 'Function "grant_appli" exists.');
SELECT has_function('public', 'session_role', '{}', 'Function "session_role" exists.');
SELECT has_function('public', 'create_account', '{text}', 'Function "create_account" exists.');
SELECT has_function('public', 'drop_account', '{name}', 'Function "drop_account" exists.');
SELECT has_function('public', 'list_accounts', '{}', 'Function "list_accounts" exists.');
SELECT has_function('public', 'is_account', '{name}', 'Function "is_account" exists.');
SELECT has_function('public', 'authenticate', '{name, text}', 'Function "authenticate" exists.');
SELECT has_function('public', 'set_opm_session', '{text}', 'Function "set_opm_session" exists.');
SELECT has_function('public', 'create_user', '{text, text, name[]}', 'Function "create_user" exists.');
SELECT has_function('public', 'drop_user', '{name}', 'Function "drop_user" exists.');
SELECT has_function('public', 'update_user', '{name, text}', 'Function "update_user" exists.');
SELECT has_function('public', 'update_current_user', '{text}', 'Function "update_current_user" exists.');
SELECT has_function('public', 'list_users', '{}', 'Function "list_users" exists.');
SELECT has_function('public', 'list_users', '{name}', 'Function "list_users(name)" exists.');
SELECT has_function('public', 'is_user', '{name}', 'Function "is_user" exists.');
SELECT has_function('public', 'is_member', '{bigint}', 'Function "is_member(bigint)" exists.');
SELECT has_function('public', 'is_member', '{name}', 'Function "is_member(name)" exists.');
SELECT has_function('public', 'is_member', '{name, name}', 'Function "is_member(name, name)" exists.');
SELECT has_function('public', 'is_admin', '{name}', 'Function "is_admin(name)" exists.');
SELECT has_function('public', 'is_admin', '{}', 'Function "is_admin" exists.');
SELECT has_function('public', 'grant_account', '{name,name}', 'Function "grant_account" exists.');
SELECT has_function('public', 'revoke_account', '{name,name}', 'Function "revoke_account" exists.');
SELECT has_function('public', 'list_warehouses', '{}', 'Function "list_warehouses" exists.');
SELECT has_function('public', 'wh_exists', '{name}', 'Function "wh_exists" exists.');
SELECT has_function('public', 'list_servers', '{}', 'Function "list_servers" exists.');
SELECT has_function('public', 'grant_server', '{bigint,name}', 'Function "grant_server" exists.');
SELECT has_function('public', 'revoke_server', '{bigint,name}', 'Function "revoke_server" exists.');
SELECT has_function('public', 'list_services', '{}', 'Function "list_services" exists.');
SELECT has_function('public', 'list_metrics', '{bigint}', 'Function "list_metrics" exists.');
SELECT has_function('public', 'update_graph_metrics', '{bigint,bigint[]}', 'Function "update_graph_metrics" exists.');
SELECT has_function('public', 'list_graphs', '{}', 'Function "list_graphs" exists.');
SELECT has_function('public', 'create_graph_for_new_metric', '{bigint}', 'Function "create_graph_for_new_metric" exists.');
SELECT has_function('public', 'clone_graph', '{bigint}', 'Function "clone_graph" exists.');
SELECT has_function('public', 'delete_graph', '{bigint}', 'Function "delete_graph" exists.');
SELECT has_function('public', 'get_sampled_metric_data', '{bigint, timestamp with time zone, timestamp with time zone, integer}', 'Function "get_sampled_metric_data" exists.');
SELECT has_function('public', 'js_time', '{timestamp with time zone}', 'Function "js_time" exists.');
SELECT has_function('public', 'js_timetz', '{timestamp with time zone}', 'Function "js_timetz" exists.');







-- Does "opm_admins" is in table roles ?
SELECT set_eq(
    $$SELECT id, rolname FROM public.roles WHERE rolname='opm_admins' AND NOT canlogin$$,
    $$VALUES (1, 'opm_admins')$$,
    'Account "opm_admins" exists in public.roles.'
);

SELECT diag(E'\n==== List warehouses and processes ====\n');

SELECT set_eq(
    $$SELECT COUNT(*) FROM list_warehouses()$$,
    $$VALUES (0)$$,
    'Should not find any warehouse.'
);

SELECT set_eq(
    $$SELECT * FROM wh_exists('wh_nagios')$$,
    $$VALUES (FALSE)$$,
    'Should not find warehouse wh_nagios.'
);

SELECT lives_ok(
    $$CREATE EXTENSION hstore$$,
    'Create extension "hstore"'
);

SELECT lives_ok(
    $$CREATE EXTENSION wh_nagios$$,
    'Create extension "wh_nagios"'
);

SELECT set_eq(
    $$SELECT * FROM list_warehouses()$$,
    $$VALUES ('wh_nagios')$$,
    'Should find warehouse wh_nagios.'
);

SELECT set_eq(
    $$SELECT * FROM wh_exists('wh_nagios')$$,
    $$VALUES (TRUE)$$,
    'Should find warehouse wh_nagios.'
);

SELECT lives_ok(
    $$DROP EXTENSION wh_nagios$$,
    'Drop extension "wh_nagios"'
);

SELECT lives_ok(
    $$DROP SCHEMA wh_nagios$$,
    'Drop schema "wh_nagios"'
);



SELECT diag(E'\n==== Check owner ====\n');


CREATE OR REPLACE FUNCTION test_owner()
RETURNS SETOF TEXT LANGUAGE plpgsql AS $$
DECLARE
    v_owner name := rolname FROM pg_roles AS r
        JOIN pg_database AS d ON r.oid = d.datdba
        WHERE datname = current_database();
BEGIN
    RETURN QUERY
        SELECT isnt_superuser( v_owner, 'The database owner should not be a superuser to validate theses tests.');

    -- schemas owner
    RETURN QUERY
        SELECT schema_owner_is( n.nspname, v_owner )
        FROM pg_catalog.pg_namespace n
        WHERE n.nspname !~ '^pg_'
            AND n.nspname <> 'information_schema';

    -- tables owner
    RETURN QUERY
        SELECT table_owner_is( n.nspname, c.relname, v_owner )
        FROM pg_catalog.pg_class c
            LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind IN ('r','')
            AND n.nspname <> 'pg_catalog'
            AND n.nspname <> 'information_schema'
            AND n.nspname !~ '^pg_toast'
            AND c.relpersistence <> 't';

    -- sequences owner
    RETURN QUERY
        SELECT sequence_owner_is(n.nspname, c.relname, v_owner)
        FROM pg_catalog.pg_class c
            LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind IN ('S','')
            AND n.nspname <> 'pg_catalog'
            AND n.nspname <> 'information_schema'
            AND n.nspname !~ '^pg_toast'
            AND c.relpersistence <> 't';

    -- functions owner
    RETURN QUERY
        SELECT function_owner_is( n.nspname, p.proname, (
                SELECT string_to_array(oidvectortypes(proargtypes), ', ')
                FROM pg_proc
                WHERE oid=p.oid
            ),
            v_owner
        )
        FROM pg_depend dep
            JOIN pg_catalog.pg_proc p ON dep.objid = p.oid
            LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
        WHERE dep.deptype= 'e' AND dep.refobjid = (
                SELECT oid FROM pg_extension WHERE extname = 'opm_core'
            )
            AND pg_catalog.pg_function_is_visible(p.oid)
            AND p.proname <> 'set_extension_owner' -- this one should be owned by a superuser
            ;

    -- owner of special set_extension_owner
    RETURN QUERY SELECT is_superuser( rolname, 'Function set_extension_owner must be owned by a superuser.')
        FROM pg_catalog.pg_roles AS r
            JOIN pg_catalog.pg_proc AS p ON (r.oid = p.proowner)
        WHERE p.proname = 'set_extension_owner'
            AND p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
END
$$;

SELECT test_owner();

SELECT diag(E'\n==== Check privileges ====\n');

-- database privs
SELECT database_privs_are(current_database(), 'public', ARRAY[]::name[]);

-- schemas privs
SELECT schema_privs_are(n.nspname, 'public', ARRAY[]::name[])
FROM pg_catalog.pg_namespace n
WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema';

-- tables privs
SELECT table_privs_are(n.nspname, c.relname, 'public', ARRAY[]::name[])
FROM pg_catalog.pg_class c
    LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','')
    AND n.nspname <> 'pg_catalog'
    AND n.nspname <> 'information_schema'
    AND n.nspname !~ '^pg_toast'
    AND c.relpersistence <> 't';

-- sequences privs
SELECT sequence_privs_are(n.nspname, c.relname, 'public', ARRAY[]::name[])
FROM pg_catalog.pg_class c
    LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('S','')
    AND n.nspname <> 'pg_catalog'
    AND n.nspname <> 'information_schema'
    AND n.nspname !~ '^pg_toast'
    AND c.relpersistence <> 't';

-- functions privs
SELECT function_privs_are( n.nspname, p.proname, (
        SELECT string_to_array(oidvectortypes(proargtypes), ', ')
        FROM pg_proc
        WHERE oid=p.oid
    ),
    'public', ARRAY[]::name[]
)
FROM pg_depend dep
    JOIN pg_catalog.pg_proc p ON dep.objid = p.oid
    LEFT JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE dep.deptype= 'e' AND dep.refobjid = (
        SELECT oid FROM pg_extension WHERE extname = 'opm_core'
    )
    AND pg_catalog.pg_function_is_visible(p.oid);


SELECT diag(E'\n==== Drop opm_core ====\n');

SELECT lives_ok(
    $$DROP EXTENSION opm_core$$,
    'Drop extension "opm_core"'
);

SELECT hasnt_extension('opm_core', 'Extension "opm_core" does not exist.');
SELECT hasnt_table('public', 'roles', 'Schema public does not contains table "roles" of opm_core.' );
SELECT hasnt_table('public', 'members', 'Schema public does not contains table "members" of opm_core.' );
SELECT hasnt_table('public', 'servers', 'Schema public does not contains table "servers" of opm_core.' );
SELECT hasnt_table('public', 'services', 'Schema public does not contains table "services" of opm_core.' );
SELECT hasnt_table('public', 'metrics', 'Schema public does not contains table "metrics" of opm_core.' );
SELECT hasnt_table('public', 'graphs', 'Schema public does not contains table "graphs" of opm_core.' );
SELECT hasnt_table('public', 'series', 'Schema public does not contains table "series" of opm_core.' );



SELECT hasnt_function('public', 'set_extension_owner', '{name}', 'Function "set_extension_owner" does not exist anymore.');
SELECT hasnt_function('public', 'create_admin', '{name, text}', 'Function "create_admin" does not exist anymore.');
SELECT hasnt_function('public', 'grant_dispatcher', '{name,name}', 'Function "grant_dispatcher" does not exist anymore.');
SELECT hasnt_function('public', 'revoke_dispatcher', '{name,name}', 'Function "revoke_dispatcher" does not exist anymore.');
SELECT hasnt_function('public', 'grant_appli', '{name}', 'Function "grant_appli" does not exist anymore.');
SELECT hasnt_function('public', 'revoke_appli', '{name}', 'Function "grant_appli" does not exist anymore.');
SELECT hasnt_function('public', 'session_role', '{}', 'Function "session_role" does not exist anymore.');
SELECT hasnt_function('public', 'create_account', '{text}', 'Function "create_account" does not exist anymore.');
SELECT hasnt_function('public', 'drop_account', '{name}', 'Function "drop_account" does not exist anymore.');
SELECT hasnt_function('public', 'list_accounts', '{}', 'Function "list_accounts" does not exist anymore.');
SELECT hasnt_function('public', 'is_account', '{name}', 'Function "is_account" does not exist anymore.');
SELECT hasnt_function('public', 'authenticate', '{name, text}', 'Function "authenticate" does not exist anymore.');
SELECT hasnt_function('public', 'set_opm_session', '{text}', 'Function "set_opm_session" does not exist anymore.');
SELECT hasnt_function('public', 'create_user', '{text, text, name[]}', 'Function "create_user" does not exist anymore.');
SELECT hasnt_function('public', 'drop_user', '{name}', 'Function "drop_user" does not exist anymore.');
SELECT hasnt_function('public', 'update_user', '{name, text}', 'Function "update_user" does not exist anymore.');
SELECT hasnt_function('public', 'update_current_user', '{text}', 'Function "update_current_user" does not exist anymore.');
SELECT hasnt_function('public', 'list_users', '{}', 'Function "list_users" does not exist anymore.');
SELECT hasnt_function('public', 'list_users', '{name}', 'Function "list_users(name)" does not exist anymore.');
SELECT hasnt_function('public', 'is_user', '{name}', 'Function "is_user" does not exist anymore.');
SELECT hasnt_function('public', 'is_member', '{bigint}', 'Function "is_member(bigint)" does not exist anymore.');
SELECT hasnt_function('public', 'is_member', '{name}', 'Function "is_member(name)" does not exist anymore.');
SELECT hasnt_function('public', 'is_member', '{name, name}', 'Function "is_member(name, name)" does not exist anymore.');
SELECT hasnt_function('public', 'is_admin', '{name}', 'Function "is_admin(name)" does not exist anymore.');
SELECT hasnt_function('public', 'is_admin', '{}', 'Function "is_admin" does not exist anymore.');
SELECT hasnt_function('public', 'grant_account', '{name,name}', 'Function "grant_account" does not exist anymore.');
SELECT hasnt_function('public', 'revoke_account', '{name,name}', 'Function "revoke_account" does not exist anymore.');
SELECT hasnt_function('public', 'list_warehouses', '{}', 'Function "list_warehouses" does not exist anymore.');
SELECT hasnt_function('public', 'wh_exists', '{name}', 'Function "wh_exists" does not exist anymore.');
SELECT hasnt_function('public', 'list_servers', '{}', 'Function "list_servers" does not exist anymore.');
SELECT hasnt_function('public', 'grant_server', '{bigint,name}', 'Function "grant_server" does not exist anymore.');
SELECT hasnt_function('public', 'revoke_server', '{bigint,name}', 'Function "revoke_server" does not exist anymore.');
SELECT hasnt_function('public', 'list_services', '{}', 'Function "list_services" does not exist anymore.');
SELECT hasnt_function('public', 'list_metrics', '{bigint}', 'Function "list_metrics" does not exist anymore.');
SELECT hasnt_function('public', 'update_graph_metrics', '{bigint,bigint[]}', 'Function "update_graph_metrics" does not exist anymore.');
SELECT hasnt_function('public', 'list_graphs', '{}', 'Function "list_graphs" does not exist anymore.');
SELECT hasnt_function('public', 'create_graph_for_new_metric', '{bigint}', 'Function "create_graph_for_new_metric" does not exist anymore.');
SELECT hasnt_function('public', 'clone_graph', '{bigint}', 'Function "clone_graph" does not exist anymore.');
SELECT hasnt_function('public', 'delete_graph', '{bigint}', 'Function "delete_graph" does not exist anymore.');
SELECT hasnt_function('public', 'get_sampled_metric_data', '{bigint, timestamp with time zone, timestamp with time zone, integer}', 'Function "get_sampled_metric_data" does not exist anymore.');
SELECT hasnt_function('public', 'js_time', '{timestamp with time zone}', 'Function "js_time" does not exist anymore.');
SELECT hasnt_function('public', 'js_timetz', '{timestamp with time zone}', 'Function "js_timetz" does not exist anymore.');


-- Finish the tests and clean up.
SELECT * FROM finish();

ROLLBACK;
