package OPM::Grapher;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group
use Mojo::Base 'OPM::Plugin';

sub register {
    my ( $self, $app ) = @_;

    # TODO: get rid of this plugin
    $app->plugin('properties');

    return $self;
}

sub register_routes {
    my ( $self, $r, $r_auth, $r_adm ) = @_;

    ## Graphs
    # show
    $r_auth->route( '/graphs/:id', id => qr/\d+/ )->name('graphs_show')
        ->to('grapher-graphs#show');

    # edit
    $r_adm->route( '/graphs/:id/edit', id => qr/\d+/ )->name('graphs_edit')
        ->to('grapher-graphs#edit');

    # remove
    $r_adm->route( '/graphs/:id/remove', id => qr/\d+/ )
        ->name('graphs_remove')->to('grapher-graphs#remove');

    # clone
    $r_adm->route( '/graphs/:id/clone', id => qr/\d+/ )->name('graphs_clone')
        ->to('grapher-graphs#clone');

    # data
    $r_auth->post('/graphs/data')->name('graphs_data')
        ->to('grapher-graphs#data');

    # show service (using name)
    $r_auth->route('/graphs/showservice/:server/:service')
        ->name('graphs_showservice')->to('grapher-graphs#showservice');

    # show server
    $r_auth->route( '/graphs/showserver/:idserver', idserver => qr/\d+/ )
        ->name('graphs_showserver')->to('grapher-graphs#showserver');

}

sub links_service {
    my ( $self, $ctrl ) = ( shift, shift );
    my $args  = @_;
    my $value = {
        icon  => 'stats',
        title => 'Graph',
        href  => $ctrl->url_for( 'graphs_showservice', @_ ) };
    return [$value];
}

1;
