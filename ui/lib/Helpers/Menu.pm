package Helpers::Menu;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2018: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';

sub register {
    my ( $self, $app ) = @_;

    $app->helper(
        user_menu => sub {
            my $self = shift;
            my $html = '';
            my $level = "user";

            if ( $self->session('user_username') ) {
                $level = "admin" if ( $self->session('user_admin') );
                $self->stash(
                    user_level => $level,
                    menu_username => $self->session('user_username') );

                if ( $Mojolicious::VERSION >= 5.00 ) {
                    $html = $self->render_to_string(
                        template => 'helpers/user_menu' );
                } else {
                    $html = $self->render(
                        template => 'helpers/user_menu',
                        partial  => 1 );
                }
            }

            return b($html);
        } );

    $app->helper(
        main_menu => sub {
            my $self = shift;
            my $html;
            my $level = "guest";
            my $dbh;
            my $sql;
            my @servers;
            my $curr_account = {
                'servers' => []
            };

            $level = "user"  if ( $self->session('user_username') );
            $level = "admin" if ( $self->session('user_admin') );

            if ($level ne "guest" ) {
                $dbh = $self->database();
                $sql = $dbh->prepare(
                    "SELECT id, hostname, COALESCE(rolname,'') AS rolname
                    FROM public.list_servers()
                    ORDER BY rolname, hostname;");
                $sql->execute();

                while ( my $row = $sql->fetchrow_hashref() ) {

                    if ( not exists $curr_account->{'rolname'}
                            or $curr_account->{'rolname'} ne $row->{'rolname'}
                       ) {
                        push @servers, \%{ $curr_account } if exists $curr_account->{'rolname'};

                        $curr_account = {
                            'rolname'  => $row->{'rolname'},
                            'servers'  => []
                        };
                    }

                    push @{ $curr_account->{'servers'} }, {
                        'id'       => $row->{'id'},
                        'hostname' => $row->{'hostname'}
                    };
                }
                push @servers, \%{ $curr_account } if exists $curr_account->{'rolname'};

                $sql->finish();
            }

            $self->stash(
                user_level => $level,
                servers    => \@servers
            );
            if ( $Mojolicious::VERSION >= 5.00 ) {
                $html =
                    $self->render_to_string( template => 'helpers/main_menu' );
            } else {
                $html =
                    $self->render( template => 'helpers/main_menu', partial => 1 );
            }

            return b($html);
        } );
}

1;
