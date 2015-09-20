package OPM::Server;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Controller';

sub adm {
    my $self       = shift;
    my $method     = $self->req->method;
    my $validation = $self->validation;
    my $sql;

    $sql = $self->prepare('SELECT hostname
        FROM public.list_servers()
        ORDER BY 1
    ');
    $sql->execute();

    $self->stash( hostnames => $sql->fetchall_arrayref( {} ) );

    return $self->render();
}

sub _is_server {
    my ( $self, $hostname ) = @_;
    my $sql = $self->prepare('SELECT COUNT(*)
        FROM public.list_servers()
        WHERE hostname = ?
    ');

    $sql->execute($hostname);

    return $sql->fetchrow() == 1;
}

sub edit {
    my $self         = shift;
    my $method       = $self->req->method;
    my $hostname     = $self->param('hostname');
    my $new_hostname = $self->param('new_hostname');

    # TODO: find a way to raise a NotFound exception
    # from another subroutine.
    return $self->render_not_found unless $self->_is_server($hostname);

    if ( $method eq 'POST' ) {{
        my $validation = $self->validation;

        $validation->required('new_hostname');
        $self->validation_error($validation);
        last if $validation->has_error;

        if ($self->proc_wrapper->rename_server(
            $hostname,
            $validation->output->{new_hostname}
        )) {
            $self->msg->info("Server renamed");
            return $self->redirect_post('servers_edit',
                hostname => $new_hostname);
        }

        $self->msg->error("Could not rename server");
    }}

    return;
}

sub list {
    my $self = shift;
    my $servers;
    my $sql = $self->prepare(
        q{
        SELECT id, hostname, COALESCE(rolname,'') AS rolname
        FROM public.list_servers()
        ORDER BY rolname, hostname
    } );
    $sql->execute();

    $servers = $sql->fetchall_groupby('rolname');
    return $self->render( servers_by_role => $servers );
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
    my $accname;
    my $server_tags;

    $sql = $self->prepare(
        q{
        SELECT hostname, COALESCE(rolname,'')
        FROM public.list_servers()
        WHERE id = ?
        LIMIT 1;
    } );
    $sql->execute($id);
    ( $hostname, $accname ) = $sql->fetchrow();

    if ( not $hostname ) {
        $self->stash(
            message => 'Server not found',
            detail  => 'This server does not exists' );
        return $self->render_not_found;
    }

    $server_tags = $self->get_tags_for_server($id);

    # create missing graphs for given server
    $self->proc_wrapper( schema => 'public' )
        ->create_graph_for_new_metric($id);

    # Fetch all services for the given server
    $sql = $self->prepare(
        q{
        SELECT s2.id AS id_service, s2.service, s1.hostname, s2.warehouse,
               s2.tags
        FROM public.list_services() s2
        JOIN public.list_servers() s1 ON s2.id_server = s1.id
        WHERE s2.id_server = ?
        ORDER BY s2.service, s2.id
    } );
    $sql->execute($id);

    $self->stash(
        services => $sql->fetchall_arrayref( {} ),
        hostname => $hostname,
        accname  => $accname,
        id       => $id,
        tags     => $server_tags,
        is_admin => $self->session('user_admin') );
    return $self->render();
}

sub service_edit_tags {
    my $self = shift;
    my $id   = $self->param('idservice');
    my @tags;
    my $rc ;
    my $sql;

    if ( $Mojolicious::VERSION < 5.48 ) {
        @tags = $self->param('tags');
    } else {
        @tags = $self->every_param('tags');
    }

    $sql = $self->prepare(
        q{
        SELECT public.update_service_tags(?, ?);
    } );

    if ( $Mojolicious::VERSION < 5.48 ) {
        $rc = $sql->execute( $id, \@tags );
    } else {
        $rc = $sql->execute( $id, @tags );
    }
    $sql->finish();
    if ( $rc ) {
        return $self->render( 'json' => { status => "success" } );
    } else {
        return $self->render( 'json' => { status => "error" } );
    }
}

sub delete {
    my $self    = shift;
    my $id = $self->param('id');

    if ( $self->proc_wrapper->drop_server( $id ) ) {
        $self->msg->info("Server deleted");
    }
    else {
        $self->msg->error("Could not delete server");
    }

    return $self->redirect_post('server_list');

}

1;
