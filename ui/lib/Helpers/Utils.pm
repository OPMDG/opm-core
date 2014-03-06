package Helpers::Utils;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group


use Mojo::Base 'Mojolicious::Plugin';

sub register {
    my ( $self, $app, $config ) = @_;
    $app->helper(
        redirect_post => sub {
            my $ctrl = shift;
            $ctrl->res->code(303);
            return $ctrl->redirect_to(@_);
        });
    $app->helper(
        format_accname => sub {
            my $ctrl = shift;
            my $accname = shift;
            return '' if ( !defined $accname );
            return $ctrl->l('Unassigned') if ( $accname eq '');
            return $accname;
        })
}

1;
