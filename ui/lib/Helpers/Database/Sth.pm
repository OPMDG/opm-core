package Helpers::Database::Sth;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base -base;

has sth => sub { };

sub AUTOLOAD {
    my $self = shift;
    my ( $package, $method ) = split /::(\w+)$/, our $AUTOLOAD;

    return $self->sth->$method( @_ );
}

sub DESTROY {
}

sub fetchall_groupby {
    my ( $self, $groupby ) = @_;
    my $results  = {};
    my $last_key = '';
    my $current_values;

    foreach my $value ( @{ $self->sth->fetchall_arrayref({}) } ) {
        my $key = $value->{$groupby};
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
