package OPM;
use Mojo::Base 'Mojolicious';

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use vars qw($VERSION);
$VERSION = '2.0.0_1';

# This method will run once at server start
sub startup {
    my $self = shift;

    # register Helpers plugins namespace
    $self->plugins->namespaces(
        [ "Helpers", "OPM", @{ $self->plugins->namespaces } ] );

    # setup charset
    $self->plugin( charset => { charset => 'utf8' } );
    $self->plugin(
        I18N => {
            namespace         => 'OPM::I18N',
            support_url_langs => [qw(en fr)]
        } );

    # load configuration
    my $config_file = $self->home . '/opm.conf';
    my $config = $self->plugin( 'JSONConfig' => { file => $config_file } );

    # setup secret passphrase
    if($config->{secrets})
    {
        $self->secrets($config->{secrets});
    }

    # startup database connection
    $self->plugin( 'database', $config->{database} || {} );

    # Load HTML Messaging plugin
    $self->plugin('messages');

    # Load others plugins
    $self->plugin('menu');
    $self->plugin('permissions');
    $self->plugin('utils');

    # CGI pretty URLs
    if ( $config->{rewrite} ) {
        $self->hook(
            before_dispatch => sub {
                my $self = shift;
                $self->req->url->base(
                    Mojo::URL->new( $config->{base_url} ) );
            } );
    }

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');

    $self->plugin( 'modules', $config->{modules} || [] );

    # Routes
    my $r      = $self->routes;
    my $r_auth = $r->bridge->to('users#check_auth');
    my $r_adm  = $r_auth->bridge->to('users#check_admin');

    # Home page
    $r_auth->route('/')->to('server#list')->name('site_home');
    $r_auth->route('/about')->to('users#about')->name('site_about');

    # Lang
    $r->route('/lang/:code')->to('lang#set')->name('lang_set');

    # User stuff
    $r->route('/login')->to('users#login')->name('users_login');
    $r_auth->route('/profile')->to('users#profile')->name('users_profile');

    $r_auth->route('/change_password')->to('users#change_password')->name('users_change_password');
    $r_auth->route('/logout')->to('users#logout')->name('users_logout');
    if ( $config->{allow_register} ) {
        $r->route('/register')->to('users#register')->name('users_register');
    }

    # User management
    $r_adm->route('/users')->to('users#list')->name('users_list');
    $r_adm->route('/users/create')->to('users#create')->name('users_create');
    $r_adm->route('/users/:rolname')->to('users#edit')->name('users_edit');
    $r_adm->route('/users/delete/:rolname')->to('users#delete')
        ->name('users_delete');
    $r_adm->route('/users/delacc/:accname/:rolname')->to('users#delacc')
        ->name('users_delacc');

    # Account management
    $r_adm->route('/accounts')->to('accounts#list')->name('accounts_list');
    $r_adm->route('/accounts/create')->to('accounts#create')
        ->name('accounts_create');
    $r_adm->route('/accounts/:accname')->to('accounts#edit')
        ->name('accounts_edit');
    $r_adm->route('/accounts/:accname/add_user')->to('accounts#add_user')
        ->name('accounts_add_user');
    $r_adm->route('/accounts/:accname/add_server')->to('accounts#add_server')
        ->name('accounts_add_server');
    $r_adm->route('/accounts/:accname/new_user')->to('accounts#new_user')
        ->name('accounts_new_user');

    $r_adm->route('/accounts/delete/:accname')->to('accounts#delete')
        ->name('accounts_delete');
    $r_adm->route('/accounts/delrol/:accname/:rolname')->to('accounts#delrol')
        ->name('accounts_delrol');
    $r_adm->route('/accounts/revokeserver/:accname/:idserver')->to('accounts#revokeserver')
        ->name('accounts_revokeserver');

    # Server management
    $r_auth->route('/server')->to('server#list')->name('server_list');
    $r_auth->route('/server/:id', id => qr/\d+/ )
        ->to('server#host')->name('server_host');
    $r_auth->route('/server/:server', id => qr/[-a-zA-Z0-9_.@]/ )
        ->to('server#host_by_name')->name('server_host_by_name');

    ## Wh_nagios management
    #
    # show all services
    $r_adm->get('/wh_nagios')->to('wh_nagios#services')->name('wh_nagios_services');
    # action (cleanup, purge), update retention or delete for multiple services
    $r_adm->post('/wh_nagios')->to('wh_nagios#services_post')->name('wh_nagios_services_post');
    # show a single service
    $r_adm->route('/wh_nagios/:id', id => qr/\d+/ )->via('GET')->to('wh_nagios#service')->name('wh_nagios_service');
    # update a single service retention or delete multiple labels
    $r_adm->route('/wh_nagios/:id', id => qr/\d+/ )->via('POST')->to('wh_nagios#service_post')->name('wh_nagios_service_post');
    # cleanup a single service
    $r_adm->route('/wh_nagios/:id/cleanup', id => qr/\d+/ )->to('wh_nagios#cleanup')->name('wh_nagios_cleanup');
    # purge a single service
    $r_adm->route('/wh_nagios/:id/purge', id => qr/\d+/ )->to('wh_nagios#purge')->name('wh_nagios_purge');
    # delete a single service
    $r_adm->route('/wh_nagios/:id/delete', id => qr/\d+/ )->to('wh_nagios#delete_service')->name('wh_nagios_delete_service');
    # delete a single label
    $r_adm->route('/wh_nagios/:id_s/delete/:id_l', id_s => qr/\d+/, id_l => qr/\d+/ )->to('wh_nagios#delete_label')->name('wh_nagios_delete_label');

    # Search bar
    $r_auth->route('/search/server')->to('search#server')->name('search_server');
}

1;
