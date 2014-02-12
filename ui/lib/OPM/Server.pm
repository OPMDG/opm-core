package OPM::Server;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Controller';

use Digest::SHA qw(sha256_hex);

sub list {
    my $self = shift;
    my $servers;
    my $sql = $self->prepare(
        q{
        SELECT id, hostname, COALESCE(rolname,'Unassigned') AS rolname
        FROM public.list_servers()
        ORDER BY rolname, hostname
    } );
    $sql->execute();

    $servers = $sql->fetchall_groupby('rolname');
    return $self->render( 'server/list', servers_by_role => $servers );
}

sub service {
    my $self = shift;
    my $sql  = $self->database->prepare(
        'SELECT s2.hostname
        FROM public.list_services() s1
        JOIN public.list_servers s2 ON s2.id = s1.id_server
        ORDER BY s1.id
    ' );

    $sql->execute();
    $self->stash( servers => $sql->fetchall_arrayref( {} ) );

    return $self->render();
}

sub host_by_name {
    my $self        = shift;
    my $server_name = $self->param('server');
    my $sql         = $self->database->prepare(
        q{
        SELECT id
        FROM public.list_servers()
        WHERE hostname = ?
        LIMIT 1;
    } );
    my $id_server;

    $sql->execute($server_name);

    return $self->redirect_to( 'server_host',
        id => @{ $sql->fetchall_arrayref() }[0] );
}

sub host {
    my $self = shift;
    my $id   = $self->param('id');
    my $sql;
    my $hostname;

    $sql = $self->prepare(
        q{
        SELECT hostname
        FROM public.list_servers()
        WHERE id = ?
        LIMIT 1;
    } );
    $sql->execute($id);
    $hostname = $sql->fetchrow();

    if ( not $hostname ) {
        $self->stash(
            message => 'Server not found',
            detail  => 'This server does not exists' );
        return $self->render_not_found;
    }

    # create missing graphs for given server
    $self->proc_wrapper( schema => 'pr_grapher' )
        ->create_graph_for_wh_nagios($id);

    # Fetch all services for the given server
    $sql = $self->prepare(
        q{
        SELECT s.id AS id_service, s.service, lower(s.state) as state
        FROM wh_nagios.list_services() s
        WHERE s.id_server = ?
        ORDER BY s.service, s.id
    } );
    $sql->execute($id);

    $self->stash(
        services => $sql->fetchall_arrayref( {} ),
        hostname => $hostname,
        id       => $id );
    return $self->render();
}

1;
