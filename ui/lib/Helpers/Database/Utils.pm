package Helpers::Database::Utils;

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

sub groupby {
    my ( $mod, $values, $sub ) = @_;
    my $results  = {};
    my $last_key = "";
    my $current_values;
    foreach my $value ( @{$values} ) {
        $_ = $value;
        my $key = &$sub( %{$value} );
        if ( $key ne $last_key ) {
            $last_key        = $key;
            $current_values  = [];
            $results->{$key} = $current_values;
        }
        push @$current_values, $value;
    }
    return $results;
}

return 1;
