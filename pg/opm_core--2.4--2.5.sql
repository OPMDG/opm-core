-- This program is open source, licensed under the PostgreSQL License.
-- For license terms, see the LICENSE file.
--
-- Copyright (C) 2012-2018: Open PostgreSQL Monitoring Development Group

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION opm_core" to load this file. \quit

-- Make public.graphs_templates dumpable if needed, assume either both table
-- and sequence are dumpable or not dumpable
DO $_$
BEGIN
    RAISE LOG 'Checking if public.graphs_templates is dumpable';
    IF (SELECT COUNT(*) = 1
        FROM pg_extension
        WHERE (select oid from pg_class where relname = 'graphs_templates') = ANY (extconfig)
        )
    THEN
        RAISE LOG 'Already dumpable, nothing to to.';
    ELSE
        RAISE LOG 'Making table dumpable.';
        PERFORM pg_catalog.pg_extension_config_dump('public.graphs_templates', '');
        PERFORM pg_catalog.pg_extension_config_dump('public.graphs_templates_id_seq', '');
    END IF;
END;
$_$ language plpgsql;
