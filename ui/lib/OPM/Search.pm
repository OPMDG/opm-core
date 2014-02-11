package OPM::Search;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Controller';

sub server {
    my $self = shift;
    my $query = $self->param('query');
    my $sql;
    my $servers;
    my $predicate;
    
    $predicate = scalar($query) ? " WHERE hostname ilike ? " : "";
    $sql = $self->prepare(qq{SELECT id, hostname as name
        FROM public.list_servers()
        $predicate
        ORDER BY 1
    });

    $sql->execute("%$query%");

    $servers = $sql->fetchall_arrayref({});
    
    return $self->render( 'json' => $servers );
}

1;
