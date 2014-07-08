-- This program is open source, licensed under the PostgreSQL License.
-- For license terms, see the LICENSE file.
--
-- Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

\unset ECHO
\i t/setup.sql

SELECT plan(77);


CREATE OR REPLACE FUNCTION test_set_opm_session(IN p_user name)
  RETURNS SETOF TEXT LANGUAGE plpgsql AS $f$
BEGIN

    RETURN QUERY
        SELECT set_eq(
            format($$SELECT public.set_opm_session(%L)$$, p_user),
            format($$VALUES (%L)$$, p_user),
            format('Set session to "%s".', p_user)
        );

    RETURN QUERY 
        SELECT results_eq(
            $$SELECT session_role()$$,
            format($$VALUES (%L::text)$$, p_user),
            format('Current OPM session is "%s".', p_user)
        );
END$f$;

SELECT diag(E'\n==== Setup environnement ====\n');

SELECT lives_ok(
    $$CREATE EXTENSION opm_core$$,
    'Create extension "opm_core"'
);

SELECT is_superuser(current_user, 'You must run these tests as superuser.');

SELECT diag(E'\n==== Create somes accounts ====\n');

SELECT set_eq(
    $$SELECT * FROM public.create_admin('opmtestadmin','opmtestadmin')$$,
    $$VALUES (2, 'opmtestadmin')$$,
    'Account "opmtestadmin" should be created.'
);


SELECT set_eq(
    $$SELECT * FROM is_admin('opmtestadmin')$$,
    $$VALUES (true)$$,
    'User "opmtestadmin" should be admin.'
);

SELECT set_eq(
    $$SELECT public.authenticate('opmtestadmin', md5('bad pass'))$$,
    $$VALUES (false)$$,
    'Failing "opmtestadmin" authentication with bad pass.'
);

SELECT set_eq(
    $$SELECT public.authenticate('opmtestadmin', md5('opmtestadminopmtestadmin'))$$,
    $$VALUES (true)$$,
    'Authenticate "opmtestadmin".'
);


SELECT test_set_opm_session('opmtestadmin');


-- Creates account "acc1"
SELECT set_eq(
    $$SELECT * FROM create_account('acc1')$$,
    $$VALUES (3, 'acc1')$$,
    'Account "acc1" should be created.'
);

-- Does "acc1" exists in table roles ?
SELECT set_eq(
    $$SELECT id, rolname FROM public.roles WHERE rolname='acc1' and NOT canlogin$$,
    $$VALUES (3, 'acc1')$$,
    'Account "acc1" exists in public.roles.'
);

-- Is "acc1" an account ?
SELECT set_eq(
    $$SELECT is_account('acc1')$$,
    $$VALUES (true)$$,
    'Account "acc1" is an account.'
);

-- Is "acc1" a user ?
SELECT set_eq(
    $$SELECT is_user('acc1')$$,
    $$VALUES (false)$$,
    'Account "acc1" is not a user.'
);

-- Creates account "acc2"
SELECT set_eq(
    $$SELECT * FROM create_account('acc2')$$,
    $$VALUES (4, 'acc2')$$,
    'Account "acc2" is created.'
);

-- Role "acc2" exists ?
SELECT set_eq(
    $$SELECT id, rolname FROM public.roles WHERE rolname='acc2' and NOT canlogin$$,
    $$VALUES (4, 'acc2')$$,
    'Account "acc2" should exists in public.roles.'
);

-- Is "acc2" an account ?
SELECT set_eq(
    $$SELECT is_account('acc2')$$,
    $$VALUES (true)$$,
    'Account "acc2" should be an account.'
);

-- Is "acc2" a user ?
SELECT set_eq(
    $$SELECT is_user('acc2')$$,
    $$VALUES (false)$$,
    'Account "acc2" should not be a user.'
);


SELECT diag(E'\n==== Create somes users ====\n');

-- Creates user "u1" in acc1
SELECT set_eq(
    $$SELECT * FROM create_user('u1', 'pass1', '{acc1}')$$,
    $$VALUES (5, 'u1')$$,
    'User "u1" in account "acc1" should be created.'
);

-- Creates user "u2"
SELECT set_eq(
    $$SELECT * FROM create_user('u2', 'pass2', '{acc2}')$$,
    $$VALUES (6, 'u2')$$,
    'User "u2" in account "acc2" should be created.'
);

-- Creates user "u3"
SELECT set_eq(
    $$SELECT * FROM create_user('u3', 'pass3', '{acc1,acc2}')$$,
    $$VALUES (7, 'u3')$$,
    'User "u3" in accounts "acc1", acc2" should be created.'
);

-- Creates user "u4"
SELECT set_eq(
    $$SELECT * FROM create_user('u4', 'pass4', '{acc1,acc2}')$$,
    $$VALUES (8, 'u4')$$,
    'User "u4" in accounts "acc1, acc2" should be created.'
);

SELECT set_eq(
    $$SELECT * FROM list_users()$$,
    $$VALUES (2, 'opm_admins', 'opmtestadmin'),
        (5, 'acc1', 'u1'),
        (7, 'acc1', 'u3'),
        (8, 'acc1', 'u4'),
        (6, 'acc2', 'u2'),
        (7, 'acc2', 'u3'),
        (8, 'acc2', 'u4')$$,
    'List all the users.'
);


SELECT set_eq(
    $$SELECT is_admin(s.n) FROM (VALUES ('u1'), ('u2'), ('u3'), ('u4')) AS s(n)$$,
    $$VALUES (false), (false), (false), (false)$$,
    'Users u1, u2, u3 and u4 should not be admin.'
);

SELECT set_eq(
    $$SELECT * FROM is_admin('not_a_user')$$,
    $$VALUES (false)$$,
    'User "not_a_user" should not exist.'
);

SELECT diag(E'\n==== Grant and revoke accounts ====\n');

SET client_min_messages TO 'warning';

SELECT throws_ok(
    $$SELECT * FROM revoke_account('u1','acc1')$$,
    $$Could not revoke account acc1 from user u1 : user must have at least one account$$,
    'Account "acc1" shoud not be removed from user "u1": only 1 account.'
);

SELECT set_eq(
    $$SELECT * FROM grant_account('u1','acc2')$$,
    $$VALUES (TRUE)$$,
    'Account "acc2" should be added to user "u1".'
);

SELECT set_eq(
    $$SELECT * FROM revoke_account('u1','acc2')$$,
    $$VALUES (TRUE)$$,
    'Account "acc2" should be removed from user "u1".'
);

SELECT throws_ok(
    $$SELECT * FROM revoke_account('u1','not_an_account')$$,
    $$One or both given roles does not exist.$$,
    'Function revoke_account should notice "not_an_account" does not exists.'
);

SELECT throws_ok(
    $$SELECT * FROM revoke_account('not_a_user','acc2')$$,
    $$One or both given roles does not exist.$$,
    'Function revoke_account should notice "not_a_user" does not exist.'
);

SELECT throws_ok(
    $$SELECT * FROM grant_account('u1','not_an_account')$$,
    'insert or update on table "members" violates foreign key constraint "members_member_fkey"',
    'Function grant_account should notice "not_an_account" does not exist.'
);

SELECT throws_ok(
    $$SELECT * FROM grant_account('not_a_user','acc2')$$,
    'insert or update on table "members" violates foreign key constraint "members_rolname_fkey"',
    'Function grant_account should notice "not_a_user" does not exist.'
);

SELECT set_eq(
    $$SELECT * FROM grant_account('u2','opm_admins')$$,
    $$VALUES (TRUE)$$,
    '"u2" should be added to "opm_admins".'
);

SELECT set_eq(
    $$SELECT is_admin('u2')$$,
    $$VALUES (TRUE)$$,
    '"u2" should be an admin.'
);

SELECT set_eq(
    $$SELECT * FROM revoke_account('u2','opm_admins')$$,
    $$VALUES (TRUE)$$,
    '"u2" should be removed from "opm_admins".'
);

SELECT set_eq(
    $$SELECT is_admin('u2')$$,
    $$VALUES (FALSE)$$,
    '"u2" should not be admin anymore.'
);

SELECT diag(E'\n==== functions list_users and list_accounts ====\n');

SELECT set_eq(
    $$SELECT * FROM list_users() WHERE rolname = 'opmtestadmin'$$,
    $$VALUES (2, 'opm_admins', 'opmtestadmin')$$,
    'Only list admin opmtestadmin.'
);

SELECT set_eq(
    $$SELECT * FROM list_users('acc1')$$,
    $$VALUES (5, 'acc1', 'u1'),
        (7, 'acc1', 'u3'),
        (8, 'acc1', 'u4')$$,
    'Only list users of account "acc1".'
);

-- User should only see account/users member of their own account
-- u3 is in both accounts

SELECT test_set_opm_session('u3');

SELECT set_eq(
    $$SELECT * FROM list_users()$$,
    $$VALUES (5, 'acc1', 'u1'),
        (7, 'acc1', 'u3'),
        (8, 'acc1', 'u4'),
        (6, 'acc2', 'u2'),
        (7, 'acc2', 'u3'),
        (8, 'acc2', 'u4')$$,
    'Only list users in the same account than u3.'
);

SELECT set_eq(
    $$SELECT * FROM list_accounts()$$,
    $$VALUES (3, 'acc1'),
        (4, 'acc2')$$,
    'Only list accounts of "u3".'
);



-- User should only see account/users member of their own account
-- u1 is only in acc1.
SELECT test_set_opm_session('u1');

SELECT set_eq(
    $$SELECT * FROM list_users()$$,
    $$VALUES (5, 'acc1', 'u1'),
        (7, 'acc1', 'u3'),
        (8, 'acc1', 'u4')$$,
    'Only list users in the same account than u1.'
);

SELECT set_eq(
    $$SELECT * FROM list_accounts()$$,
    $$VALUES (3, 'acc1')$$,
    'Only list accounts of "u1".'
);

SELECT test_set_opm_session('opmtestadmin');

SELECT set_eq(
    $$SELECT * FROM list_users()$$,
    $$VALUES (5, 'acc1', 'u1'),
        (7, 'acc1', 'u3'),
        (8, 'acc1', 'u4'),
        (6, 'acc2', 'u2'),
        (7, 'acc2', 'u3'),
        (8, 'acc2', 'u4'),
        (2, 'opm_admins', 'opmtestadmin')$$,
    'Admin can see all users.'
);

SELECT set_eq(
    $$SELECT * FROM list_accounts()$$,
    $$VALUES (1, 'opm_admins'),
        (3, 'acc1'),
        (4, 'acc2')$$,
    'Admin can see all accounts.'
);

SELECT diag(E'\n==== functions list_servers, and grant_server and revoke_server ====\n');

SELECT set_eq(
    $$SELECT COUNT(*) FROM public.list_servers()$$,
    $$VALUES (0)$$,
    'Should not have any server present.'
);

SELECT lives_ok($$INSERT INTO public.servers (hostname) VALUES
    ('hostname1'),('hostname2')
    $$,
    'Insert two servers'
);

SELECT set_eq(
    $$SELECT * FROM public.list_servers()$$,
    $$VALUES (1::bigint,'hostname1',NULL,'{}'::text[]),
    (2,'hostname2',NULL,'{}'::text[])$$,
    'Admin can see all servers.'
);

SELECT set_eq(
    $$SELECT * FROM public.grant_server(1, 'acc1')$$,
    $$VALUES (true)$$,
    'Grant server "hostname1" to "acc1".'
);

SELECT test_set_opm_session('u1');


SELECT set_eq(
    $$SELECT * FROM public.list_servers()$$,
    $$VALUES (1::bigint,'hostname1','acc1','{}'::text[])$$,
    '"u1" should only see server "hostname1".'
);

SELECT test_set_opm_session('opmtestadmin');

SELECT set_eq(
    $$SELECT * FROM public.revoke_server(1,'acc1')$$,
    $$VALUES (true)$$,
    'Revoke server "hostname1" from "acc1".'
);


SELECT diag(E'\n==== Update user ====\n');

SELECT set_eq(
    $$SELECT password FROM public.roles WHERE rolname = 'u1'$$,
    $$SELECT md5('pass1u1')$$,
    'Password for user "u1" should be "pass1".'
);

SELECT set_eq(
    $$SELECT * FROM public.update_user('donotexists','somepassword')$$,
    $$VALUES (false)$$,
    'Changing password of an unexisting user should return false.'
);

SELECT set_eq(
    $$SELECT * FROM public.update_user('u1','newpassword')$$,
    $$VALUES (true)$$,
    'Changing password of user "u1" should return true.'
);

SELECT set_eq(
    $$SELECT password FROM public.roles WHERE rolname = 'u1'$$,
    $$SELECT md5('newpasswordu1')$$,
    'Password for user "u1" should be "newpassword".'
);

SELECT diag(E'\n==== Drop admin and user ====\n');

-- Drop admin "admin1"
/*SELECT set_eq(
    $$SELECT * FROM drop_user('admin1')$$,
    $$VALUES (8, 'admin1')$$,
    'User "admin1" is deleted using drop_user.'
);

SELECT hasnt_role('admin1', 'Role "admin1" should not exist anymore.');

SELECT set_hasnt(
    $$SELECT * FROM list_users()$$,
    $$VALUES (8, 'opm_admins', 'admin1')$$,
    'User "admin1" is not listed by list_users() anymore.'
);

SELECT set_hasnt(
    $$SELECT id, rolname FROM public.roles WHERE rolname = 'admin1'$$,
    $$VALUES (8, 'admin1')$$,
    'User "admin1" is not in table "public.roles" anymore.'
);*/

-- User u1 belongs to acc1 only

-- Drop user "u1"
SELECT set_eq(
    $$SELECT * FROM drop_user('u1')$$,
    $$VALUES (5, 'u1')$$,
    'User "u1" deleted using drop_user.'
);

SELECT set_hasnt(
    $$SELECT * FROM list_users()$$,
    $$VALUES (5, 'acc1', 'u1')$$,
    'User "u1" should not be listed by list_users() anymore.'
);

SELECT set_hasnt(
    $$SELECT id, rolname FROM public.roles WHERE rolname = 'u1'$$,
    $$VALUES (5, 'u1')$$,
    'User "u1" is not in table "public.roles" anymore.'
);

-- User u4 belongs to acc1 and acc2

-- Drop user "u4"
SELECT set_eq(
    $$SELECT * FROM drop_user('u4')$$,
    $$VALUES (8, 'u4')$$,
    'User "u4" deleted unsing drop_user.'
);

SELECT set_hasnt(
    $$SELECT * FROM list_users()$$,
    $$VALUES (8, 'acc1', 'u4'),
        (8, 'acc2', 'u4')$$,
    'User "u4" not listed by list_users anymore.'
);

SELECT set_hasnt(
    $$SELECT id, rolname FROM public.roles WHERE rolname = 'u4'$$,
    $$VALUES (8, 'u4')$$,
    'User "u4" is not in table "public.roles" anymore.'
);


SELECT diag(E'\n==== Drop accounts ====\n');

-- Drop "acc2"
SELECT set_eq(
    $$SELECT * FROM drop_account('acc2')$$,
    $$VALUES (6, 'u2'), (4, 'acc2')$$,
    'Account "acc2" should be deleted by drop_account.'
);

SELECT set_eq(
    $$SELECT * FROM list_users() WHERE NOT public.is_admin(rolname)$$,
    $$VALUES (7, 'acc1', 'u3')$$,
    'List_users should only return "u3".'
);

-- test role existance-related functions on "acc2"
-- They all should returns NULL
SELECT set_eq(
    $$SELECT * FROM is_account('acc2')$$,
    $$VALUES (false)$$,
    'Account "acc2" is not an OPM account anymore.'
);

SELECT set_eq(
    $$SELECT is_user('acc2')$$,
    $$VALUES (false)$$,
    'is_user do not return the "acc2" account.'
);

SELECT set_eq(
    $$SELECT rolname FROM public.roles WHERE rolname = 'u3'$$,
    $$VALUES ('u3')$$,
    'User "u3" is still listed in public.roles.'
);

-- Drop account "acc1"
SELECT set_eq(
    $$SELECT * FROM drop_account('acc1')$$,
    $$VALUES (7, 'u3'), (3, 'acc1')$$,
    'Account "acc1" should be deleted.'
);

SELECT set_eq(
    $$SELECT count(*) FROM list_users()$$,
    $$VALUES (1::bigint)$$,
    'Function list_users() list nothing.'
);

-- Dropping opm_admin is not allowed.

SELECT throws_matching(
    $$SELECT * FROM drop_account('opm_admins')$$,
    'can not be deleted!',
    'Account opm_admins can not be deleted.'
);

SELECT set_eq(
    $$SELECT count(*) FROM public.roles$$,
    $$VALUES (2::bigint)$$,
    'Table "public.roles" contains one account.'
);

-- Finish the tests and clean up.
SELECT * FROM finish();

ROLLBACK;
