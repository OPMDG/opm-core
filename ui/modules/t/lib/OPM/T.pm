package OPM::T;

use Mojo::Base 'Mojolicious::Plugin';

sub register {
    my ( $self, $app, $config ) = @_;

    # Routes
    my $r       = $app->routes->route('/t');
    my $r_auth  = $r->bridge->to('user#check_auth');
    my $r_adm   = $r->bridge->to('user#check_admin');

    $r->route('/test')->to('t-test#start')->name('test_start');
    $r->route('/list')->to('t-test#list')->name('test_list');

}

1;
