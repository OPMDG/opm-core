package Helpers::Menu;

# This program is open source, licensed under the PostgreSQL Licence.
# For license terms, see the LICENSE file.

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';
use Data::Dumper;

sub register {
    my ( $self, $app ) = @_;

    $app->helper(
        user_menu => sub {
            my $self = shift;
            my $html = '';

            if ( $self->session('user_username') ) {
                $self->stash(
                    menu_username => $self->session('user_username') );

                $html = $self->render(
                    template => 'helpers/user_menu',
                    partial  => 1 );
            }

            return b($html);
        } );

    $app->helper(
        top_menu => sub {
            my $self = shift;
            my $html;

            my $level = "guest";
            $level = "user"  if ( $self->session('user_username') );
            $level = "admin" if ( $self->session('user_admin') );

            $self->stash( user_level => $level );
            $html =
                $self->render( template => 'helpers/top_menu', partial => 1 );

            return b($html);
        } );
}

1;
