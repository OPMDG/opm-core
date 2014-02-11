package Helpers::Database::ProcWrapper;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base -base;

has db         => sub { };
has schema     => sub { return "public" };
has connection => sub { };
has is_from    => sub {0};

sub AUTOLOAD {
    my $self = shift,
        my ( $package, $method ) = split /::(\w+)$/, our $AUTOLOAD;
    my $schema       = $self->schema;
    my $qualified_fn = "$schema.$method";
    return $self->db->db_sub_one( $self->connection, $qualified_fn, @_ );
}

sub DESTROY {
}

return 1;
