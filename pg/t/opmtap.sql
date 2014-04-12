-- This file extends pgTAP with a collection of missing funcctions

CREATE OR REPLACE FUNCTION _extension_properties(NAME,
    OUT extname NAME, OUT rolname NAME, OUT nspname NAME
)
AS $$
    SELECT e.extname, r.rolname, n.nspname
    FROM pg_extension AS e
        JOIN pg_namespace AS n ON (e.extnamespace=n.oid)
        JOIN pg_roles AS r ON (e.extowner=r.oid)
    WHERE extname = $1;
$$ LANGUAGE SQL;

-- has_extension( extension, description )
CREATE OR REPLACE FUNCTION has_extension( NAME, TEXT )
RETURNS TEXT AS $$
    SELECT ok( (_extension_properties($1)).extname IS NOT NULL, $2);
$$ LANGUAGE SQL;

-- has_extension( extension )
CREATE OR REPLACE FUNCTION has_extension( NAME )
RETURNS TEXT AS $$
    SELECT has_extension( $1, 'Extension ' || quote_ident($1) || ' should exists');
$$ LANGUAGE SQL;

-- hasnt_extension( extension, description )
CREATE OR REPLACE FUNCTION hasnt_extension( NAME, TEXT )
RETURNS TEXT AS $$
    SELECT ok( (_extension_properties($1)).extname IS NULL, $2);
$$ LANGUAGE SQL;

-- hasnt_extension( extension )
CREATE OR REPLACE FUNCTION hasnt_extension( NAME )
RETURNS TEXT AS $$
    SELECT hasnt_extension( $1, 'Extension ' || quote_ident($1) || ' should not exists');
$$ LANGUAGE SQL;

-- extension_ower_is( extension, owner, description)
CREATE OR REPLACE FUNCTION extension_owner_is( NAME, NAME, TEXT )
RETURNS TEXT AS $$
    SELECT ok( (_extension_properties($1)).rolname = $2, $3);
$$ LANGUAGE SQL;

-- extension_ower_is( extension, owner)
CREATE OR REPLACE FUNCTION extension_owner_is( NAME, NAME )
RETURNS TEXT AS $$
    SELECT extension_owner_is( $1, $2, 'Owner of extension ' || quote_ident($1) || ' should be ' || quote_ident($2) );
$$ LANGUAGE SQL;

-- extension_schema_is( extension, owner, description)
CREATE OR REPLACE FUNCTION extension_schema_is( NAME, NAME, TEXT )
RETURNS TEXT AS $$
    SELECT ok( (_extension_properties($1)).nspname = $2, $3);
$$ LANGUAGE SQL;

-- extension_schema_is( extension, owner)
CREATE OR REPLACE FUNCTION extension_schema_is( NAME, NAME )
RETURNS TEXT AS $$
    SELECT extension_schema_is( $1, $2, 'Schema of extension ' || quote_ident($1) || ' should be ' || quote_ident($2) );
$$ LANGUAGE SQL;


-- PATCH is_member_of( group, user[], description )
-- Original function use pg_user, thus failing tests for nested NOLOGIN
-- roles.
CREATE OR REPLACE FUNCTION is_member_of( NAME, NAME[], TEXT )
RETURNS TEXT AS $$
DECLARE
    missing text[];
BEGIN
    IF NOT _has_role($1) THEN
        RETURN fail( $3 ) || E'\n' || diag (
            '    Role ' || quote_ident($1) || ' does not exist'
        );
    END IF;

    SELECT ARRAY(
        SELECT quote_ident($2[i])
          FROM generate_series(1, array_upper($2, 1)) s(i)
          LEFT JOIN pg_catalog.pg_roles ON rolname = $2[i]
         WHERE oid IS NULL
            OR NOT oid = ANY ( _grolist($1) )
         ORDER BY s.i
    ) INTO missing;
    IF missing[1] IS NULL THEN
        RETURN ok( true, $3 );
    END IF;
    RETURN ok( false, $3 ) || E'\n' || diag(
        '    Users missing from the ' || quote_ident($1) || E' group:\n        ' ||
        array_to_string( missing, E'\n        ')
    );
END;
$$ LANGUAGE plpgsql;

-- PATCH _fprivs_are ( TEXT, NAME, NAME[], TEXT )
-- original one use NAME as first parameter leading to function
-- signature truncature because NAME's max length is 64
CREATE OR REPLACE FUNCTION _fprivs_are ( TEXT, NAME, NAME[], TEXT )
RETURNS TEXT AS $$
DECLARE
    grants TEXT[] := _get_func_privs($2, $1);
BEGIN
    IF grants[1] = 'undefined_function' THEN
        RETURN ok(FALSE, $4) || E'\n' || diag(
            '    Function ' || $1 || ' does not exist'
        );
    ELSIF grants[1] = 'undefined_role' THEN
        RETURN ok(FALSE, $4) || E'\n' || diag(
            '    Role ' || quote_ident($2) || ' does not exist'
        );
    END IF;
    RETURN _assets_are('privileges', grants, $3, $4);
END;
$$ LANGUAGE plpgsql;
