package Helpers::Utils;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2015: Open PostgreSQL Monitoring Development Group

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
            foreach my $opm_plugin ( values %{$app->opm_plugins()} ) {
                foreach
                    my $link ( @{ $opm_plugin->$method_name( $ctrl, @_ ) } )
                {
                    push( @{$links}, $link );
                }
            }
            return $links;
        } );
    $app->helper(
        format_link => sub {
            my ( $ctrl, $link ) = ( shift, shift );
            return b(
                $ctrl->tag('a' => ( %{ $link->{a} } ) => sub {
                    $ctrl->tag('i' => ( %{ $link->{i} } ) => '' ) . $link->{display};
                })
            );
        } );

    $app->helper(
        format_links => sub {
            my $ctrl   = shift;
            my $values = [];
            foreach my $link ( @{ $ctrl->get_links(@_) } ) {
                push( @{$values}, $app->format_link($link) );
            }
            return b( join( '', @{$values} ) );
        } );

    $app->helper(
        get_unassigned => sub {
            return "Unassigned";
        }
    );

    $app->helper(
        format_accname => sub {
            my $ctrl    = shift;
            my $accname = shift;
            my %ret = (
                link => '',
                name => ''
            );
            return %ret if ( !defined $accname );
            if ( $accname eq '' or $accname eq $ctrl->get_unassigned() ) {
                $ret{link} = $ctrl->get_unassigned();
                $ret{name} = $ctrl->l($ctrl->get_unassigned());
            } else {
                $ret{link} = $accname;
                $ret{name} = $accname;
            }
            return %ret;
        } );

    $app->helper(
        get_details => sub {
            my ( $ctrl, $context ) = ( shift, shift );
            my $method_name = "details_$context";
            my $details     = [];
            foreach my $opm_plugin ( values %{$app->opm_plugins()} ) {
                foreach
                    my $detail ( @{ $opm_plugin->$method_name( $ctrl, @_ ) } )
                {
                    push( @{$details}, $detail );
                }
            }
            return $details;
        } );
    $app->helper(
        format_detail => sub {
            my ( $ctrl, $detail ) = ( shift, shift );
            return b(
                qq(<span class="$detail->{class}">$detail->{title}</span>));
        } );

    $app->helper(
        format_details => sub {
            my $ctrl   = shift;
            my $values = [];
            foreach my $detail ( @{ $ctrl->get_details(@_) } ) {
                push( @{$values}, $app->format_detail($detail) );
            }
            return b( join( '', @{$values} ) );
        } );

    $app->helper(
        get_tags_for_server => sub {
            my $ctrl      = shift;
            my $server_id = shift;
            my $sth;
            my $server_tags;
            $sth = $ctrl->prepare(
                qq{
                SELECT unnest(g.tags) as tag
                FROM public.list_graphs( ? ) g
                GROUP BY tag
                ORDER BY tag
            } );
            $sth->execute($server_id);
            $server_tags = $ctrl->database->selectcol_arrayref( $sth );
            $sth->finish;
            return $server_tags;
        } );
}

1;
