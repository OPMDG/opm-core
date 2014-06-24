package OPM::Graphs;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Controller';

sub show {
    my $self = shift;
    my $id   = $self->param('id');
    my $hostname;
    my $accname;

    # Get the graph
    my $sth = $self->prepare(
        qq{SELECT CASE WHEN s.hostname IS NOT NULL THEN s.hostname || '::' ELSE '' END || graph AS graph,description, s.id AS id_server, s.hostname, g.id
        FROM public.list_graphs() g
        LEFT JOIN public.list_servers() s ON g.id_server = s.id
        WHERE g.id = ?} );

    $sth->execute($id);
    my $graph = $sth->fetchrow_hashref;
    $sth->finish;

    # Check if it exists (this can be reach by url)
    if ( !defined $graph ) {
        return $self->render_not_found;
    }

    $hostname = $graph->{'hostname'};

    # Get the rolname
    $accname = get_rolname_by_hostname($self, $hostname);

    my $graph_list = [];
    if ( scalar $hostname ) {
        $sth = $self->prepare(
            qq{SELECT g.id, g.graph as graphname
            FROM public.list_servers() s
            JOIN public.list_graphs() g ON s.id = g.id_server
            WHERE s.hostname = ? AND g.id <> ?
            ORDER BY 2}
        );
        $sth->execute( $hostname, $id );
        $graph_list = $sth->fetchall_arrayref( {} );
    }
    return $self->render(
        'graphs/show',
        server_id  => $graph->{id_server},
        graphs     => [$graph],
        hostname   => $hostname,
        accname    => $accname,
        graph_list => $graph_list,
        is_admin   => $self->session('user_admin') );
}

sub showservice {
    my $self         = shift;
    my $hostname     = $self->param('server');
    my $service_name = $self->param('service');
    my $server_id;
    my $services;
    my $graphs;
    my $accname;

    # Get the graphs associated with the given hostname and servicename
    my $sth = $self->prepare(
        q{
        SELECT g.id, CASE
            WHEN s2.hostname IS NOT NULL THEN s2.hostname || '::'
            ELSE ''
        END || graph AS graph,
        g.description, s2.id AS id_server, s2.hostname
        FROM  public.list_services() AS s1
        JOIN public.list_servers() AS s2 ON s2.id = s1.id_server
        JOIN public.list_graphs() g ON g.id_server = s2.id
            AND g.id_service = s1.id
        WHERE s2.hostname = ? AND s1.service = ?
        ORDER BY g.graph;
    } );

    $sth->execute( $hostname, $service_name );
    $graphs = $sth->fetchall_arrayref( {} );

    $sth->finish;

    # Check if it exists
    if ( @{$graphs} < 1 ) {
        return $self->render_not_found;
    }

    # Get the rolname
    $accname = get_rolname_by_hostname($self, $hostname);

    $server_id = $graphs->[0]{'id_server'};

    if ($server_id) {

        # Get other available services from the same server
        my $sth = $self->prepare(
            qq{
            SELECT service
            FROM public.list_services()
            WHERE id_server = ? AND service <> ?
            ORDER BY service
        } );

        $sth->execute( $server_id, $service_name );
        $services = $sth->fetchall_arrayref( {} );
        $sth->finish;
    }

    return $self->render(
        graphs    => $graphs,
        server_id => $server_id,
        hostname  => $hostname,
        accname   => $accname,
        services  => $services,
        is_admin  => $self->session('user_admin') );
}

sub showserver {
    my $self      = shift;
    my $server_id = $self->param('idserver');
    my $period    = $self->param('period');
    my $servers;
    my $graphs;
    my $hostname;
    my $accname;

    # Get the graphs
    my $sth = $self->prepare(
        qq{
        SELECT g.id, CASE WHEN s.hostname IS NOT NULL THEN s.hostname || '::' ELSE '' END || graph AS graph,description,s.hostname
        FROM public.list_graphs() g
        JOIN public.list_servers() s ON g.id_server = s.id
        WHERE g.id_server = ?
        ORDER BY  g.graph
    } );
    $sth->execute($server_id);
    $graphs = $sth->fetchall_arrayref( {} );
    $hostname = $graphs->[0]{'hostname'};
    $sth->finish;

    # Get other available servers
    $sth = $self->prepare(
        qq{
        SELECT id, hostname
        FROM public.list_servers()
        WHERE id <> ?
        ORDER BY hostname
    } );
    $sth->execute($server_id);
    $servers = $sth->fetchall_arrayref( {} );
    $sth->finish;

    # Get the rolname
    $accname = get_rolname_by_hostname($self, $hostname);

    return $self->render(
        'graphs/showserver',
        graphs    => $graphs,
        hostname  => $hostname,
        accname   => $accname,
        server_id => $server_id,
        servers   => $servers,
        is_admin  => $self->session('user_admin') );
}

sub edit {
    my $self = shift;

    my $id = $self->param('id');
    my $e  = 0;
    my $graph;
    my $accname;
    my $hostname;
    my $id_server;

    # Get the graph, and the service if a service is associated
    my $sth = $self->prepare(
        qq{SELECT graph, description,
                config::text, string_agg(id_server::text, ',') AS id_server
            FROM public.list_graphs()
            WHERE id = ?
            GROUP BY 1,2,3} );
    $sth->execute($id);
    $graph = $sth->fetchrow_hashref();
    $sth->finish();

    # Check if it exists
    if ( !defined $graph ) {
        return $self->render_not_found;
    }

    $id_server = $graph->{id_server};

    $self->flash( 'id_server', $id_server );

    # Save the form
    if ( $self->req->method =~ m/^POST$/i ) {

        # process the input data
        my $form = $self->req->params->to_hash;

        # Action depends on the name of the button pressed
        if ( exists $form->{cancel} ) {
            return $self->redirect_to( 'graphs_show', id => $id );
        }

        if ( exists $form->{drop} ) {
            return $self->redirect_to( 'graphs_remove', id => $id );
        }

        if ( exists $form->{clone} ) {
            return $self->redirect_to( 'graphs_clone', id => $id );
        }

        if ( exists $form->{save} ) {
            if ( $form->{graph} =~ m!^\s*$! ) {
                $self->msg->error("Missing graph name");
                $e = 1;
            }
            if ( not defined $form->{'labels'} ) {
                $self->msg->error("Can't remove all labels");
                return $self->redirect_to( 'graphs_edit', id => $id );
            }

            if ( !$e ) {
                my $rc;

                # Prepare the configuration: save and clean the $form
                # hashref to keep only the properties, so that we can
                # use the plugin
                delete $form->{save};
                $graph = $form->{graph};
                delete $form->{graph};
                my $description =
                    ( $form->{description} =~ m!^\s*$! )
                    ? undef
                    : $form->{description};
                delete $form->{description};

                my $props = $self->properties->validate($form);
                if ( !defined $props ) {
                    $self->msg->error(
                        "Bad input, please double check the options");
                    return $self->render;
                }

                # Save the properties actually sent
                # If a property is missing, library/grapher default value will be used
                my $json   = Mojo::JSON->new;
                my $config = $json->encode($props);

                $sth = $self->prepare(
                    qq{SELECT public.edit_graph(?, ?, ?, ?)} );
                if (
                    !defined $sth->execute( $id, $graph, $description, $config ) )
                {
                    $self->render_exception( $self->database->errstr );
                    $sth->finish();
                    $self->database->rollback();
                    return;
                }
                $rc = $sth->fetchrow();
                $sth->finish;

                unless ($rc) {
                    $self->msg->error("Error while saving graph.");
                    return $self->redirect_to( 'graphs_show', id => $id );
                }

                ## Set labels for this graph
                my @labels = ();
                if ( ref $form->{'labels'} eq 'ARRAY' ) {
                    @labels = @{ $form->{'labels'} };
                }
                else {
                    push @labels => $form->{'labels'};
                }

                $sth = $self->prepare(qq{
                    SELECT public.update_graph_metrics(?, ?)
                });

                if ( !defined $sth->execute( $id, \@labels ) ) {
                    $self->render_exception( $self->database->errstr );
                    $sth->finish();
                    $self->database->rollback();
                    return;
                }
                $sth->finish();

                $self->msg->info("Graph saved");
                return $self->redirect_to( 'graphs_show', id => $id );
            }
        }

        $self->render;
    }

    if ( !$e ) {

        $sth = $self->prepare(
            qq{
                SELECT l.id_service, l.id_metric, l.label, l.unit,
                    l.available AS checked, s.service
                FROM public.list_metrics(?) AS l
                JOIN public.list_services() AS s
                    ON l.id_service = s.id
                ORDER BY l.label, l.unit
            } );

        if ( !defined $sth->execute($id) ) {
            $self->render_exception( $self->database->errstr );
            $sth->finish();
            $self->database->rollback();
            return;
        }

        my @labels;

        my $row;

        while ( defined( $row = $sth->fetchrow_hashref ) ) {
            $row->{'unit'} = 'no unit' if $row->{'unit'} eq '';
            push @labels, { %{$row} };
            $self->req->params->append( "labels", $row->{'id_metric'} )
                if $row->{'checked'};
        }

        $sth->finish();

        # Get the rolname
        ($accname,$hostname) = get_rolname_hostname_by_graph_id($self, $id);
        $sth->finish;

        # Prepare properties
        my $json   = Mojo::JSON->new;
        my $config = $json->decode( $graph->{config} );
        delete $graph->{config};

        # Send each configuration value to prefill form
        foreach my $p ( keys %$config ) {
            $self->param( $p, $config->{$p} );
        }

        # Prefill the rest
        foreach my $p ( keys %$graph ) {
            $self->param( $p, $graph->{$p} );
        }

        # Is the graph associated with a service ?
        $self->stash(
            'id_server' => $id_server,
            'labels'    => \@labels,
            'accname'   => $accname,
            'hostname'  => $hostname,
            'graph'     => $graph->{'graph'} );
    }
    $self->render;
}

sub remove {
    my $self      = shift;
    my $id        = $self->param('id');
    my $id_server = $self->flash('id_server');
    my $sth;

    unless ($id_server) {

        # Get the graph, and the service if a service is associated
        $sth = $self->prepare(
            qq{
            SELECT id_server
            FROM public.list_graphs()
            WHERE id = ?
        } );

        unless ( defined $sth->execute($id) ) {
            $self->render_exception( $self->database->errstr );
            $sth->finish;
            $self->database->rollback;
            return;
        }

        $id_server = $sth->fetchrow();

        $sth->finish;
    }

    # Get the graph, and the service if a service is associated
    $sth = $self->prepare(
        qq{
        SELECT * FROM public.delete_graph(?)
    } );

    unless ( defined $sth->execute($id) ) {
        $self->render_exception( $self->database->errstr );
        $sth->finish;
        $self->database->rollback();
        return;
    }
    my $rc = $sth->fetchrow();
    $sth->finish;

    if ($rc) {
        $self->msg->info("Graph deleted.");
    }
    else {
        $self->msg->error("Graph could not be deleted.");
    }

    if (   ( defined $self->flash('saved_route') )
        && ( defined $self->flash('stack') ) )
    {
        return $self->redirect_to( $self->flash('saved_route'),
            $self->flash('stack') );
    }

    return $self->redirect_to( 'server_host', id => $id_server );
}

sub clone {
    my $self = shift;
    my $id   = $self->param('id');
    my $new_id;

    # Clone the graph and its associated labels
    my $sth = $self->prepare(
        "SELECT * FROM public.clone_graph(?)"
    );

    unless ( defined $sth->execute( $id ) ) {
        $self->render_exception( $self->database->errstr );
        $sth->finish;
        $self->database->rollback();
        return;
    }

    ($new_id) = $sth->fetchrow;
    $sth->finish;

    $self->msg->info("Graph cloned, please edit it.");

    return $self->redirect_to( 'graphs_edit', id => $new_id );
}

sub data {
    my $self = shift;
    my $id       = $self->param('id');
    my $from     = $self->param("from");
    my $to       = $self->param("to");
    my $config;
    my $isservice = 0;
    my $data      = [];
    my $json      = Mojo::JSON->new;

    # Double check the input
    if ( !defined $id ) {
        return $self->render( 'json' => { error => "post: Bad input" } );
    }

    # When a graph id is received, retrieve the properties from the DB
    my $sth = $self->prepare(
        qq{SELECT config FROM public.list_graphs() WHERE id = ?}
    );
    $sth->execute($id);

    $config = $sth->fetchrow();

    if ( defined $config ) {
        $config = $json->decode($config);
    }

    $sth = $self->prepare(
        qq{SELECT s.hostname || '::' || g.graph AS graph,description
        FROM public.list_graphs() g
        JOIN public.list_servers() s ON s.id = g.id_server
        WHERE g.id = ?} );
    $sth->execute($id);
    my ( $graphtitle, $graphsubtitle ) = $sth->fetchrow();
    $sth->finish();

    $config->{'title'}    = $graphtitle;
    $config->{'subtitle'} = $graphsubtitle;

    $sth = $self->prepare(
        qq{
        SELECT id_metric, label, unit
        FROM public.list_metrics(?)
        WHERE available
        ORDER BY label, unit;
    } );
    $sth->execute($id);


    my $series = {};
    $from = substr $from, 0, -3;
    $to   = substr $to,   0, -3;

    my $sql = $self->prepare(
        "SELECT public.js_time(timet), value FROM public.get_sampled_metric_data(?, to_timestamp(?), to_timestamp(?), ?);"
    );

    while ( my ( $id_metric, $label, $unit ) = $sth->fetchrow() ) {
        $sql->execute( $id_metric, $from, $to, 300 ) ;
        $series->{$label} = [];
        while ( my ( $x, $y ) = $sql->fetchrow() ) {
            push @{ $series->{$label} },
                [ 0 + $x, ( $y eq "NaN" ? undef : 0.0 + $y ) ];
        }
        $sql->finish();
        push @{$data}, { data => $series->{$label}, label => $label };

        # Buggy with multiple units!
        $config->{'yaxis_unit'} = $unit;
    }
    $config->{'yaxis_autoscale'}       = $json->true;
    $config->{'yaxis_autoscaleMargin'} = 0.2;

    $sth->finish;

    if ( !scalar(@$data) ) {
        return $self->render( 'json' => { error => "Empty output" } );
    }

    return $self->render(
        'json' => {
            series     => $data,
            properties => $self->properties->to_plot($config)
        } );
}

sub get_rolname_by_hostname {
    my $self = shift;
    my $hostname = shift;
    my $accname;

    my $sth = $self->prepare(
        q{
        SELECT COALESCE(rolname,'')
        FROM public.list_servers()
        WHERE hostname = ?
    });
    $sth->execute($hostname);
    $accname = $sth->fetchrow();
    $sth->finish();
    return $accname;
}

sub get_rolname_hostname_by_graph_id {
    my $self = shift;
    my $id_graph = shift;
    my $accname;
    my $hostname;;

    my $sth = $self->prepare(
        q{
        SELECT COALESCE(s.rolname,''),s.hostname
        FROM public.list_graphs() g
        JOIN public.list_servers() s ON g.id_server = s.id
        WHERE g.id = ?
    });
    $sth->execute($id_graph);
    ($accname,$hostname) = $sth->fetchrow();
    $sth->finish();
    return ($accname,$hostname);
}

1;
