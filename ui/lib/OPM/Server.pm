package OPM::Server;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;
use Digest::SHA qw(sha256_hex);

sub list {
    my $self = shift;
    my $dbh  = $self->database();
    my $sql;
    my @servers;
    my $curr_role = {
        'servers' => []
    };

    $sql = $dbh->prepare(
        "SELECT id, hostname, COALESCE(rolname,'') AS rolname
        FROM public.list_servers()
        ORDER BY rolname, hostname;");
    $sql->execute();

    while ( my $row = $sql->fetchrow_hashref() ) {

        $row->{'rolname'} = 'Unassigned' unless $row->{'rolname'};

        if ( not exists $curr_role->{'rolname'}
            or $curr_role->{'rolname'} ne $row->{'rolname'}
        ) {
            push @servers, \%{ $curr_role } if exists $curr_role->{'rolname'};

            $curr_role = {
                'rolname'  => $row->{'rolname'},
                'servers'  => []
            };
        }

        push @{ $curr_role->{'servers'} }, {
            'id'       => $row->{'id'},
            'hostname' => $row->{'hostname'}
        };
    }
    push @servers, \%{ $curr_role } if exists $curr_role->{'rolname'};
    $sql->finish();

    $self->stash( servers => \@servers );

    $dbh->disconnect();
    $self->render();
}

sub service {
    my $self = shift;
    my $dbh  = $self->database();
    my $sql;

    $sql = $dbh->prepare(
        "SELECT s1.id, s2.hostname FROM public.list_services() s1 JOIN public.list_servers s2 ON s2.id = s1.id_server ORDER BY 1;"
    );
    $sql->execute();
    my $servers = [];
    while ( my $v = $sql->fetchrow() ) {
        push @{$servers}, { hostname => $v };
    }
    $sql->finish();

    $self->stash( servers => $servers );

    $dbh->disconnect();
    $self->render();
}

sub host_by_name {
    my $self        = shift;
    my $dbh         = $self->database();
    my $server_name = $self->param('server');
    my $id_server;

    my $sth = $dbh->prepare(q{
        SELECT id
        FROM public.list_servers()
        WHERE hostname = ?
    });
    $sth->execute($server_name);
    $id_server = $sth->fetchrow();

    $sth->finish;
    $dbh->disconnect;

    return $self->redirect_to('server_host',
        id => $id_server
    );
}

sub host {
    my $self = shift;
    my $dbh  = $self->database();
    my $id   = $self->param('id');
    my $sql;
    my $row;
    my $hostname;
    my @services;

    $sql = $dbh->prepare(q{
        SELECT hostname
        FROM public.list_servers()
        WHERE id = ?
    });
    $sql->execute($id);
    $hostname = $sql->fetchrow();
    $sql->finish();

    if ( not $hostname ){
        $dbh->disconnect();
        $self->stash(
            message => 'Server not found',
            detail => 'This server does not exists'
        );
        return $self->render_not_found;
    }

    # create missing graphs for given server
    # FIXME: handle error
    $sql = $dbh->prepare("SELECT pr_grapher.create_graph_for_wh_nagios(?)");
    $sql->execute($id);
    $sql->finish();

    # Fetch all services for the given server
    $sql = $dbh->prepare(q{
        SELECT s.id AS id_service, s.service, lower(s.state) as state 
        FROM wh_nagios.list_services() s
        WHERE s.id_server = ?
        ORDER BY s.service, s.id
    });
    # FIXME: handle error
    $sql->execute($id);

    push @services, $row while $row = $sql->fetchrow_hashref();
    $sql->finish();

    $self->stash(
        services => \@services,
        hostname => $hostname,
        id => $id
    );

    $dbh->disconnect();
    $self->render();
}

1;
