package OPM;
use Mojo::Base 'Mojolicious';

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2013: Open PostgreSQL Monitoring Development Group

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

    # setup secret passphrase XXX
    $self->secret('Xwyfe-_d:y~Dr+p][Vs9KY+e3gmP=c_|s7hQExF#b|4r4^gO|');

    # startup database connection
    $self->plugin( 'database', $config->{database} || {} );

    # Load HTML Messaging plugin
    $self->plugin('messages');

    # Load others plugins
    $self->plugin('menu');
    $self->plugin('permissions');

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
    my $r_auth = $r->bridge->to('user#check_auth');
    my $r_adm  = $r_auth->bridge->to('user#check_admin');

    # Home page
    $r_auth->route('/')->to('server#list')->name('site_home');
    $r_auth->route('/help')->to('site#help')->name('site_help');

    # Lang
    $r->route('/lang/:code')->to('lang#set')->name('lang_set');

    # User stuff
    $r->route('/login')->to('user#login')->name('user_login');
    $r_auth->route('/profile')->to('user#profile')->name('user_profile');
    $r_auth->route('/logout')->to('user#logout')->name('user_logout');
    if ( $config->{allow_register} ) {
        $r->route('/register')->to('user#register')->name('user_register');
    }

    # User management
    $r_adm->route('/user')->to('user#list')->name('user_list');
    $r_adm->route('/user/create')->to('user#create')->name('user_create');
    $r_adm->route('/user/:rolname')->to('user#edit')->name('user_edit');
    $r_adm->route('/user/delete/:rolname')->to('user#delete')
        ->name('user_delete');
    $r_adm->route('/user/delacc/:accname/:rolname')->to('user#delacc')
        ->name('user_delacc');

    # Account management
    $r_adm->route('/account')->to('account#list')->name('account_list');
    $r_adm->route('/account/create')->to('account#create')
        ->name('account_create');
    $r_adm->route('/account/:accname')->to('account#edit')
        ->name('account_edit');
    $r_adm->route('/account/delete/:accname')->to('account#delete')
        ->name('account_delete');
    $r_adm->route('/account/delrol/:accname/:rolname')->to('account#delrol')
        ->name('account_delrol');
    $r_adm->route('/account/revokeserver/:accname/:idserver')->to('account#revokeserver')
        ->name('account_revokeserver');

    # Server management
    $r_auth->route('/server')->to('server#list')->name('server_list');
    $r_auth->route('/server/:id')->to('server#host')->name('server_host');

    # Search bar
    $r_auth->route('/search/server')->to('search#server')->name('search_server');
}

1;
