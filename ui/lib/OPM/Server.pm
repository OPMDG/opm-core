package OPM::Server;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2013: Open PostgreSQL Monitoring Development Group

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
        ORDER BY rolname;");
    $sql->execute();

    while ( my $row = $sql->fetchrow_hashref() ) {

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

sub host {
    my $self = shift;
    my $dbh  = $self->database();
    my $id   = $self->param('id');
    my $sql;

    $sql = $dbh->prepare("SELECT COUNT(*) FROM public.list_servers() WHERE id = ?");
    $sql->execute($id);
    my $found = ( $sql->fetchrow() == 1 );
    $sql->finish();

    if (! $found){
        $dbh->disconnect();
        $self->stash(
            message => 'Server not found',
            detail => 'This server does not exists'
        );
        return $self->render_not_found;
    }

    # FIXME: handle pr_grapher dependancy
    $sql = $dbh->prepare("SELECT pr_grapher.create_graph_for_wh_nagios(?)");
    $sql->execute($id);
    $sql->finish();
    $dbh->commit();

    $dbh = $self->database();

    # FIXME: handle pr_grapher and wh_nagios dependancy
    $sql = $dbh->prepare(
        "SELECT s.id AS id_service, s.service, lower(s.state) as state,
            lg.id AS id_graph, lg.graph
        FROM wh_nagios.list_services() s
        JOIN pr_grapher.list_wh_nagios_graphs() lg
            ON lg.id_service = s.id
        WHERE s.id_server = ?
        ORDER BY s.service, s.id;
        "
    );
    $sql->execute($id);

    my $curr_service = { 'id' => -1 };
    my @services;
    while ( my $row = $sql->fetchrow_hashref() ) {
        if ( $curr_service->{'id'} != $row->{'id_service'} ) {
            push @services, \%{ $curr_service } if $curr_service->{'id'} != -1;
            $curr_service = {
                'id'          => $row->{'id_service'},
                'service'     => $row->{'service'},
                'state'       => $row->{'state'},
                'graphs'      => []
            };
        }

        push @{ $curr_service->{'graphs'} }, {
            'id_graph' => $row->{'id_graph'},
            'graph'    => $row->{'graph'}
        };
    }
    push @services, \%{ $curr_service } if $curr_service->{'id'} != -1;
    $sql->finish();

    $sql = $dbh->prepare(
        "SELECT hostname FROM public.list_servers() WHERE id = ?");
    $sql->execute($id);
    my $hostname = $sql->fetchrow();
    $sql->finish();

    $self->stash( services => \@services, hostname => $hostname, id => $id );

    $dbh->disconnect();
    $self->render();
}

1;
