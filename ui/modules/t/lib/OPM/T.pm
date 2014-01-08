package OPM::T;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Plugin';

sub register {
    my ( $self, $app, $config ) = @_;

    # Routes
    my $r       = $app->routes->route('/t');
    my $r_auth  = $r->bridge->to('users#check_auth');
    my $r_adm   = $r->bridge->to('users#check_admin');

    $r->route('/test')->to('t-test#start')->name('test_start');
    $r->route('/list')->to('t-test#list')->name('test_list');

}

1;
