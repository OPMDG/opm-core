package OPM::Grapher;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2013: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Plugin';

sub register {
    my ( $self, $app, $config ) = @_;

    # Load properties helper
    $app->plugin( 'properties' );

    # Routes
    my $r      = $app->routes->route('/grapher');
    my $r_auth = $r->bridge->to('user#check_auth');
    my $r_adm  = $r_auth->bridge->to('user#check_admin');

    # Graphs
    $r_auth->route( '/graphs/:id', id => qr/\d+/ )->name('graphs_show')
        ->to('grapher-graphs#show');
    $r_adm->route( '/graphs/:id/edit', id => qr/\d+/ )
        ->name('graphs_edit')
        ->to('grapher-graphs#edit');
    $r_adm->route( ':id_server/graphs/:id/remove',
            id => qr/\d+/,
            id_server => qr/\d+/ )
        ->name('graphs_remove')
        ->to('grapher-graphs#remove');
    $r_adm->route( '/graphs/:id/clone', id => qr/\d+/ )
        ->name('graphs_clone')
        ->to('grapher-graphs#clone');
    $r_auth->post('/graphs/data')->name('graphs_data')
        ->to('grapher-graphs#data');
    $r_auth->route( '/graphs/showservice/:id', id => qr/\d+/ )
        ->name('graphs_showservice')
        ->to('grapher-graphs#showservice');
    $r_auth->route( '/graphs/showserver/:idserver',
            idserver => qr/\d+/ )
        ->name('graphs_showserver')
        ->to('grapher-graphs#showserver');

}

1;
