package Helpers::Utils;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';

sub register {
    my ( $self, $app, $config ) = @_;
    $app->helper(
        redirect_post => sub {
            my $ctrl = shift;
            $ctrl->res->code(303);
            return $ctrl->redirect_to(@_);
        } );
    $app->helper(
        get_links => sub {
            my ( $ctrl, $context ) = ( shift, shift );
            my $method_name = "links_$context";
            my $links       = [];
            foreach my $opm_plugin ( values $app->opm_plugins ) {
                foreach
                    my $link ( @{ $opm_plugin->$method_name( $ctrl, @_ ) } )
                {
                    push( $links, $link );
                }
            }
            return $links;
        } );
    $app->helper(
        format_link => sub {
            my ( $ctrl, $link ) = ( shift, shift );
            return b(
                qq(<a href="$link->{href}"><i class="glyphicon glyphicon-$link->{icon}"></i>$link->{title}</a>)
            );
        } );

    $app->helper(
        format_links => sub {
            my $ctrl   = shift;
            my $values = [];
            foreach my $link ( @{ $app->get_links(@_) } ) {
                push( $values, $app->format_link($link) );
            }
            return b( join( '', @{$values} ) );
        } );

    $app->helper(
        format_accname => sub {
            my $ctrl    = shift;
            my $accname = shift;
            return '' if ( !defined $accname );
            return $ctrl->l('Unassigned') if ( $accname eq '' );
            return $accname;
        } );
}

1;
