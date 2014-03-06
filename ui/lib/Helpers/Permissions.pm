package Helpers::Permissions;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Plugin';

has target => sub { };

sub register {
    my ( $self, $app ) = @_;

    $app->helper(
        perm => sub {
            my $ctrl = shift;
            $self->target($ctrl);
            return $self;
        } );
}

sub update_info {
    my $self = shift;
    my $data = ref $_[0] ? $_[0] : {@_};

    # Does the cookie expires ?
    if ( defined $data->{'stay_connected'} ){
        $self->target->session(expiration => 0);
    } else {
        # Default expiration : 1 hour
        $self->target->session(expiration => 3600);
    }

    # save every needed information transmitted
    foreach my $info (qw/username password admin/) {
        if ( exists $data->{$info} ) {
            $self->target->session( 'user_' . $info => $data->{$info} );
        }
    }

    return;
}

sub remove_info {
    my $self = shift;

    map { delete $self->target->session->{$_} }
        qw(user_username user_password user_admin);
}

sub is_authd {
    my $self = shift;

    if ( $self->target->session('user_username') ) {
        return 1;
    }

    return 0;
}

sub is_admin {
    my $self = shift;

    return 0 unless defined $self->target->session('user_admin');

    if ( $self->target->session('user_admin') ) {
        return 1;
    }
    return 0;
}

1;
