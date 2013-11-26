package OPM::Grapher;

use Mojo::Base 'Mojolicious::Plugin';

sub register {
    my ( $self, $app, $config ) = @_;

    # Load properties helper
    $app->plugin( 'properties',
        file => $config->{home} . '/default_options.json' );

    # Routes
    my $r      = $app->routes->route('/grapher');
    my $r_auth = $r->bridge->to('user#check_auth');
    my $r_adm  = $r_auth->bridge->to('user#check_admin');

    # Graphs
    $r_auth->route('/graphs')->to('grapher-graphs#list')->name('graphs_list');
    $r_auth->route('/graphs/add')->to('grapher-graphs#add')
        ->name('graphs_add');
    $r_auth->route( '/graphs/:id', id => qr/\d+/ )->to('grapher-graphs#show')
        ->name('graphs_show');
    $r_adm->route( '/graphs/:id/edit', id => qr/\d+/ )
        ->to('grapher-graphs#edit')->name('graphs_edit');
    $r_adm->route( ':id_server/graphs/:id/remove',
        id => qr/\d+/,
        id_server => qr/\d+/
    )->to('grapher-graphs#remove')->name('graphs_remove');
    $r_adm->route( '/graphs/:id/clone',
        id => qr/\d+/,
    )->to('grapher-graphs#clone')->name('graphs_clone');
    $r_auth->post('/graphs/data')->to('grapher-graphs#data')
        ->name('graphs_data');
    $r_auth->route( '/graphs/showservice/:id', id => qr/\d+/ )->to('grapher-graphs#showservice')
        ->name('graphs_showservice');
    $r_auth->route( '/graphs/showserver/:idserver', idserver => qr/\d+/ )->to('grapher-graphs#showserver')
        ->name('graphs_showserver');

    #Properties
    $r_auth->route('/properties')->to('grapher-properties#defaults')
        ->name('properties_defaults');

    # Categories
    $r_auth->get('/categories')->to('grapher-categories#list')
        ->name('categories_list');
    $r_auth->route('/categories/add')->to('grapher-categories#add')
        ->name('categories_add');
    $r_auth->route( '/categories/:id/edit', id => qr/\d+/ )
        ->to('grapher-categories#edit')->name('categories_edit');
    $r_auth->route( '/categories/:id/remove', id => qr/\d+/ )
        ->to('grapher-categories#remove')->name('categories_remove');

}

1;
