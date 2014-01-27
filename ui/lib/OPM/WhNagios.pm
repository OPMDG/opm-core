package OPM::WhNagios;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;

# Specific route for POST action on multiple services
sub services_post {
    my $self = shift;

    my $form_data = $self->req->params->to_hash;

    # Check if some services have been selected
    if ( !defined $form_data->{'chk'} ) {
        $self->msg->warning('No service selected');
        return $self->redirect_to('wh_nagios_services');
    }

    # Specific action for each submit button
    if ( defined $form_data->{'cleanup'} ) {
        _cleanup($self, $form_data->{'chk'});
    }
    if ( defined $form_data->{'purge'} ) {
        _purge($self, $form_data->{'chk'});
    }
    if ( defined $form_data->{'delete'} ) {
        _delete_service($self, $form_data->{'chk'});
    }
    if ( defined $form_data->{'servalid'} ) {
        _update_servalid($self, $form_data)
    }

    # Redirect to GET route, so refresh won't post data again
    return $self->redirect_to('wh_nagios_services');
}

# Specific route for POST action on a single service
sub service_post {
    my $self = shift;

    my $form_data = $self->req->params->to_hash;
    my $service_id = $self->param('id');

    # action for retention update
    if ( defined $form_data->{'servalid'} ) {
        _update_servalid($self, $form_data);
    }

    # action for label deletion
    if ( defined $form_data->{'delete'} ) {
        # Check if some labels have been selected
        if ( !defined $form_data->{'chk'} ) {
            $self->msg->warning('No label selected');
            return $self->redirect_to('wh_nagios_service', id => $service_id);
        }

        _delete_label($self, $service_id, $form_data->{'chk'});
    }

    # Redirect to GET route, so refresh won't post data again
    return $self->redirect_to('wh_nagios_service', id => $service_id);
}

# Specific route for GET action
sub services {
    my $self = shift;
    my $dbh  = $self->database();
    my $sql;
    my @services;
    my $curr_host = {
        'services' => []
    };

    $sql = $dbh->prepare(
        "SELECT s1.hostname, s1.id as server_id, s2.id, s2.service,
          (CURRENT_TIMESTAMP - s2.last_cleanup)::interval(0) as last_cleanup,
          s2.servalid, s2.state,
          (s2.newest_record- s2.oldest_record)::interval(0) AS stored_interval,
          ((s2.newest_record - s2.oldest_record) > s2.servalid) AS need_purge
          FROM public.list_servers() s1
          JOIN wh_nagios.list_services() s2 ON s1.id = s2.id_server
          ORDER BY s1.hostname, s2.service;"
    );
    $sql->execute();

    while ( my $row = $sql->fetchrow_hashref() ) {
        if ( not exists $curr_host->{'hostname'}
            or $curr_host->{'hostname'} ne $row->{'hostname'}
        ) {
            push @services, \%{ $curr_host } if exists $curr_host->{'hostname'};

            $curr_host = {
                'hostname'  => $row->{'hostname'},
                'server_id'        => $row->{'server_id'},
                'services'  => []
            };
        }

        # Generate needed class for template, service state
        my $class = 'inverse';
        $class = 'success' if ( lc($row->{'state'}) eq 'ok' );
        $class = 'warning' if ( lc($row->{'state'}) eq 'warning' );
        $class = 'important' if ( lc($row->{'state'}) eq 'critical' );
        # Generate needed class for template, service retention state
        my $need_purge = 'info';
        if ( defined $row->{'servalid'} ) {
            $need_purge = ( $row->{'need_purge'} ? 'warning' : 'success' );
        }

        push @{ $curr_host->{'services'} }, {
            'id'              => $row->{'id'},
            'service'         => $row->{'service'},
            'last_cleanup'    => $row->{'last_cleanup'},
            'servalid'        => $row->{'servalid'},
            'state'           => $row->{'state'},
            'stored_interval' => $row->{'stored_interval'},
            'need_purge'      => $need_purge,
            'class'           => $class
        };
    }
    push @services, \%{ $curr_host } if exists $curr_host->{'hostname'};
    $sql->finish();

    $self->stash( services => \@services );

    $dbh->disconnect();
    return $self->render();
}

# Display a single service
sub service {
    my $self = shift;
    my $dbh  = $self->database();
    my $sql;
    my $service_id = $self->param('id');
    my $hostname;

    $sql = $dbh->prepare("SELECT s1.hostname
      FROM public.servers s1
      JOIN wh_nagios.services s2 ON s1.id = s2.id_server
      WHERE s2.id = ?");

    $sql->execute($service_id);
    $hostname = $sql->fetchrow();

    # Test if the service exists and is linked to a server
    if ( !defined $hostname ) {
        $sql->finish();
        $dbh->disconnect();
        $self->msg->warning("Service not found or isn't linked to a server");
        return $self->render_not_found();
    }

    $sql = $dbh->prepare(
        "SELECT id, service, last_modified,
          age(CURRENT_DATE, last_modified) AS Age_last_modified,
          creation_ts::timestamp(0) as creation_ts,
          (CURRENT_TIMESTAMP - creation_ts)::interval(0) AS age_creation_ts,
          last_cleanup::timestamp(0) as last_cleanup,
          (CURRENT_TIMESTAMP - last_cleanup)::interval(0) AS age_last_cleanup,
          servalid, UPPER(state) AS state,
          oldest_record,
          (CURRENT_TIMESTAMP - oldest_record)::interval(0) AS age_oldest_record,
          newest_record,
          (CURRENT_TIMESTAMP - newest_record)::interval(0) AS age_newest_record,
          (newest_record - oldest_record)::interval(0) AS stored_interval,
          ((newest_record - oldest_record) > servalid) AS need_purge
          FROM wh_nagios.list_services() WHERE id = ?;"
    );
    $sql->execute( $service_id );

    my $servicerow = $sql->fetchrow_hashref();

    # Test if the service exists
    if ( !defined $servicerow ) {
        $sql->finish();
        $dbh->disconnect();
        $self->msg->warning('Service not found');
        return $self->redirect_to('wh_nagios_services');
    }

    # Generate needed class for template, service state
    my $badge = "inverse";
    if ( $servicerow->{state} eq "OK" ) {
        $badge = "success";
    } elsif ( $servicerow->{state} eq "WARNING" ) {
        $badge = "warning";
    } elsif ( $servicerow->{state} eq "CRITICAL" ) {
        $badge = "important";
    }
    $servicerow->{badge} = $badge;

    # Generate needed class for template, service retention state
    my $purge_class = 'info';
    if ( defined $servicerow->{'servalid'} ) {
        $purge_class = ( $servicerow->{'need_purge'} ? 'warning' : 'success' );
    }
    $servicerow->{purge_class} = $purge_class;

    $sql = $dbh->prepare(
        "SELECT id_label, label, unit, min, max, critical, warning
          FROM wh_nagios.list_label( ? )
          ORDER BY label ;"
    );
    $sql->execute( $service_id );

    my $labels = [];

    my $sql_range;
    while ( my $labelrow = $sql->fetchrow_hashref() ) {
        # Get first and last record, interval and check if it's ok with related service's servalid
        my $sql_range = $dbh->prepare("SELECT min(date_records) AS min_rec, max(date_records) as max_rec,
            age(max(date_records), min(date_records)) AS stored_interval,
            (age(max(date_records), min(date_records)) > ?) AS need_purge
            FROM wh_nagios.counters_detail_" . $labelrow->{id_label});

        $sql_range->execute($servicerow->{servalid});

        my $range = $sql_range->fetchrow_hashref();

        # Generate needed class for template, label retention state
        my $label_purge_class = 'info';
        if ( defined $servicerow->{'servalid'} ) {
            $label_purge_class = ( $range->{'need_purge'} ? 'warning' : 'success' );
        }

        # Merge hashes
        $labelrow->{label_purge_class} = $label_purge_class;
        @{$labelrow}{keys %{$range}} = values %{$range};

        push @{$labels},  $labelrow ;
    }

    $sql->finish();

    $self->stash( hostname => $hostname, service => $servicerow, labels => $labels );

    $dbh->disconnect();
    return $self->render();
}

sub cleanup {
    my $self = shift;
    # single service cleanup is done in the same function as for multiple services
    # The function expects an array as input
    my @tab = ();
    push(@tab, $self->param('id'));
    _cleanup($self, \@tab);
    return $self->redirect_to('wh_nagios_services');
}

sub purge {
    my $self = shift;
    # single service purge is done in the same function as for multiple services
    # The function expects an array as input
    my @tab = ();
    push(@tab, $self->param('id'));
    _purge($self, \@tab);
    return $self->redirect_to('wh_nagios_services');
}

sub delete_service {
    my $self = shift;
    # single service deletion is done in the same function as for multiple services
    # The function expects an array as input
    my @tab = ();
    push(@tab, $self->param('id'));
    _delete_service( $self, \@tab);
    return $self->redirect_to('wh_nagios_services');
}

sub delete_label {
    my $self = shift;
    # single slabel deletion is done in the same function as for multiple labels
    # The function expects an array as input
    my @tab = ();
    push(@tab, $self->param('id_l'));
    _delete_label( $self, $self->param('id_s'), \@tab);
    # Redirect to the currently displayed service
    return $self->redirect_to('wh_nagios_service', id => $self->param('id_s'));
}

sub _cleanup {
    my $self = shift;
    my $id_servers = shift;
    # make sure we have an array even if only 1 value
    # It happens when only 1 checkbox is selected
    $id_servers = [ $id_servers ] if ref($id_servers) ne 'ARRAY';

    my $dbh  = $self->database();

    my $sql = $dbh->prepare('SELECT * FROM wh_nagios.cleanup_service( ? ) ; ');
    foreach my $id (@{$id_servers}){
        if ( $id =~ m/^\d+$/ ) {
            if ( !$sql->execute($id)){
                $sql->finish();
                $dbh->disconnect();
                $self->msg->error('Database error');
                # Exit on first error, some services might be updated
                return;
            }
        }
    }
    $self->msg->info('Service(s) cleaned');

    $sql->finish();

    $dbh->disconnect();
    return;
}

sub _update_servalid {
    my $self = shift;
    my $form_data = shift;
    my $dbh  = $self->database();
    my $sql;
    my $id_servers = $form_data->{'chk'};
    # make sure we have an array even if only 1 value
    # It happens when only 1 checkbox is selected
    $id_servers = [ $id_servers ] if ref($id_servers) ne 'ARRAY';

    if ( defined $form_data->{'validity'} and $form_data->{'validity'} ne '' ) {
        # overall interval
        # check interval validity
        $sql = $dbh->prepare('SELECT CAST( ? AS INTERVAL) ;');
        if ( !$sql->execute($form_data->{'validity'}) ) {
            $self->msg->error('Invalid interval');
            $sql->finish();
            $dbh->disconnect();
            return;
        }
        # Generate comma separated numeric id values,
        # as we are calling a function with VARIADIC argument
        $id_servers = join(',', grep { $_ =~ '^\d+$' } @{$id_servers});

        # Check if there is at least 1 id
        if ( $id_servers eq '' ) {
            $self->msg->warning('No server selected');
            return;
        }

        $sql = $dbh->prepare( "SELECT * FROM wh_nagios.update_services_validity( ?, $id_servers ) ; ");
        if ( !$sql->execute($form_data->{'validity'}) ) {
            $self->msg->error('Database error');
        } else {
            $self->msg->info('Service(s) updated');
        }
    } else {
        # specific interval per service
        my $sql_val = $dbh->prepare('SELECT CAST( ? AS INTERVAL) ;');
        $sql = $dbh->prepare( 'SELECT * FROM wh_nagios.update_services_validity( ?, ? ) ; ');
        my $servalid;
        foreach my $id (@{$id_servers}){
            if ( $id =~ m/^\d+$/ ) {
                $servalid = $form_data->{'servalid_val_' . $id};
                # check interval validity
                if ( !$sql_val->execute($servalid) ){
                    $self->msg->error('Invalid interval');
                    $sql_val->finish();
                    $sql->finish();
                    $dbh->disconnect();
                    # Exit on first error, some services might be updated
                    return;
                }
                if ( !$sql->execute($servalid, $id) ) {
                    $sql_val->finish();
                    $sql->finish();
                    $dbh->disconnect();
                    $self->msg->error('Database error');
                    # Exit on first error, some services might be updated
                    return;
                }
            }
        }
        $sql_val->finish();
        $self->msg->info('Service(s) updated');
    }
    $sql->finish();
    $dbh->disconnect();

    return;
}

sub _purge {
    my $self = shift;
    my $ids = shift;
    # make sure we have an array even if only 1 value
    # It happens when only 1 checkbox is selected
    $ids = [ $ids ] if ref($ids) ne 'ARRAY';
    # Generate comma separated numeric id values,
    # as we are calling a function with VARIADIC argument
    my $id_servers = join(',', grep { $_ =~ '^\d+$' } @{$ids});

    # Check if there is at least 1 id
    if ( $id_servers eq '' ) {
        $self->msg->warning('No server selected');
        return;
    }

    my $dbh  = $self->database();
    my $sql = $dbh->prepare("SELECT * FROM wh_nagios.purge_services( $id_servers ) ; ");
    if ( !$sql->execute ){
        $sql->finish();
        $dbh->disconnect();
        $self->msg->error('Database error');
        return;
    }

    $self->msg->info('Service(s) purged');

    $sql->finish();

    $dbh->disconnect();
    return;
}

sub _delete_service {
    my $self = shift;
    my $ids = shift;
    # make sure we have an array even if only 1 value
    # It happens when only 1 checkbox is selected
    $ids = [ $ids ] if ref($ids) ne 'ARRAY';
    # Generate comma separated numeric id values,
    # as we are calling a function with VARIADIC argument
    my $id_servers = join(',', grep { $_ =~ '^\d+$' } @{$ids});

    # Check if there is at least 1 id
    if ( $id_servers eq '' ) {
        $self->msg->warning('No server selected');
        return;
    }

    my $dbh  = $self->database();
    my $sql = $dbh->prepare(
        "SELECT * FROM wh_nagios.delete_services( $id_servers ) ;"
    );

    if ( !$sql->execute() ) {
        $self->msg->error('Database error');
        $sql->finish();
        $dbh->disconnect();
        return;
    };

    my $rc = $sql->fetchrow();
    if ( $rc ){
        $self->msg->info('Service(s) deleted');
    } else{
        $self->msg->warning('Error during service(s) deletion');
    }

    $sql->finish();

    $dbh->disconnect();
    return;
}

sub _delete_label {
    my $self = shift;
    my $id_service = shift;
    my $ids = shift;
    # make sure we have an array even if only 1 value
    # It happens when only 1 checkbox is selected
    $ids = [ $ids ] if ref($ids) ne 'ARRAY';

    # Generate comma separated numeric id values,
    # as we are calling a function with VARIADIC argument
    my $id_labels = join(',', grep { $_ =~ '^\d+$' } @{$ids});

    # Check if there is at least 1 id
    if ( $id_labels eq '' ) {
        $self->msg->warning('No label selected');
        return;
    }

    my $dbh  = $self->database();
    my $sql = $dbh->prepare(
        "SELECT * FROM wh_nagios.delete_labels( $id_labels ) ;"
    );

    if ( !$sql->execute() ) {
        $self->msg->error('Database error');
        $sql->finish();
        $dbh->disconnect();
        return;
    };

    my $rc = $sql->fetchrow();
    if ( $rc ){
        $self->msg->info('Label(s) deleted');
    } else{
        $self->msg->warning('Error during label(s) deletion');
    }

    $sql->finish();

    $dbh->disconnect();
    return;
}

1;
