-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION wh_nagios" to load this file. \quit

-- This program is open source, licensed under the PostgreSQL License.
-- For license terms, see the LICENSE file.
--
-- Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

SET statement_timeout TO 0 ;

SET client_encoding = 'UTF8';
SET check_function_bodies = false;

DROP FUNCTION public.update_user(IN p_account name, IN p_password text);

DROP FUNCTION public.update_current_user(text);
