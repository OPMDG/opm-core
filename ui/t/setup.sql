DROP DATABASE IF EXISTS opm;
DROP ROLE IF EXISTS opm;
DROP ROLE IF EXISTS opm_roles;
DROP ROLE IF EXISTS opm_admins;
DROP ROLE IF EXISTS dba;
DROP ROLE IF EXISTS test;
DROP ROLE IF EXISTS entreprise;
DROP ROLE IF EXISTS user1;
DROP ROLE IF EXISTS user2;
DROP ROLE IF EXISTS user3;
DROP ROLE IF EXISTS acc1;
DROP ROLE IF EXISTS acc2;

CREATE DATABASE opm;
\c opm


CREATE EXTENSION opm_core;
CREATE EXTENSION hstore;
CREATE EXTENSION wh_nagios;
CREATE EXTENSION pr_grapher;
CREATE EXTENSION pr_grapher_wh_nagios;

SELECT create_account('dba');

SELECT create_user('test','password','{dba}');
SELECT public.grant_account('test','opm_admins');

SELECT create_account('entreprise');
SELECT create_user('user1','user1','{entreprise}');
SELECT create_user('user2','user2','{entreprise}');

insert into wh_nagios.hub (data) select ('{MIN,0,WARNING,10,VALUE,' || (0.4 + (i::numeric(4,1)/10))::numeric(5,2) || ',CRITICAL,50,LABEL,fic_value,HOSTNAME,my_server,MAX,0,UOM,\"\",SERVICESTATE,OK,TIMET,' || 1338552000 + i * 3600|| ',SERVICEDESC,\"SYSTM - Load\"}')::text[] from generate_series (0,999) i;
insert into wh_nagios.hub (data) select ('{MIN,0,WARNING,10,VALUE,' || (1.4 + (i::numeric(4,1)/10))::numeric(5,2) || ',CRITICAL,50,LABEL,fic_value2,HOSTNAME,my_server,MAX,0,UOM,\"\",SERVICESTATE,OK,TIMET,' || 1338552000 + i * 3600|| ',SERVICEDESC,\"SYSTM - Load\"}')::text[] from generate_series (0,999) i;
SELECT wh_nagios.dispatch_record();
SELECT public.grant_server(1,'test');
insert into wh_nagios.hub (data) select ('{MIN,0,WARNING,10,VALUE,' || (2.4 + (i::numeric(4,1)/10))::numeric(5,2) || ',CRITICAL,50,LABEL,other_fic_value,HOSTNAME,my_server,MAX,0,UOM,\"\",SERVICESTATE,OK,TIMET,' || 1338552000 + i * 3600|| ',SERVICEDESC,\"SYSTM - Load\"}')::text[] from generate_series (0,999) i;
SELECT wh_nagios.dispatch_record();
