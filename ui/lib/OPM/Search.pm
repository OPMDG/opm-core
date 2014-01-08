package OPM::Search;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Controller';

sub server {
    my $self = shift;
    my $query = $self->param('query');
    my $dbh  = $self->database();
    if (scalar $query){
        $query = " WHERE hostname ilike '%$query%' ";
    }
    my $sql = $dbh->prepare("SELECT id,hostname FROM public.list_servers() $query ORDER BY 1;");
    $sql->execute();
    my $servers = [];
    while ( my ($id, $hostname) = $sql->fetchrow() ) {
        push @{$servers}, { id => $id, name => $hostname };
    }
    $sql->finish();
    $dbh->disconnect();
    $self->render( 'json' => $servers );
}

1;
