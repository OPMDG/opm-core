-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION wh_nagios" to load this file. \quit

-- This program is open source, licensed under the PostgreSQL License.
-- For license terms, see the LICENSE file.
--
-- Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

SET statement_timeout TO 0 ;

SET client_encoding = 'UTF8';
SET check_function_bodies = false;

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
    SELECT count(*) = 1 INTO v_exists FROM public.list_users()
    WHERE rolname = p_rolname ;
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

