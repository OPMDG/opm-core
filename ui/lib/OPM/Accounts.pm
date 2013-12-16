package OPM::Accounts;

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

    my $method = $self->req->method;
    if ( $method =~ m/^POST$/i ) {    # Create a new account
                                      # process the input data
        my $form_data = $self->req->params->to_hash;

        # Check input values
        my $e = 0;
        if ( $form_data->{accname} =~ m/^\s*$/ ) {
            $self->msg->error("Empty account name.");
            $e = 1;
        }
        if ( !$e ) {
            $sql =
                $dbh->prepare( "SELECT public.create_account('"
                    . $form_data->{accname}
                    . "');" );
            if ( $sql->execute() ) {
                $self->msg->info("Account created");
                $dbh->commit() if (!$dbh->{AutoCommit});
            }
            else {
                $self->msg->error("Could not create account");
                $dbh->rollback() if (!$dbh->{AutoCommit});
            }
            $sql->finish();
        }
    }

    $sql = $dbh->prepare(
        'SELECT accname FROM public.list_accounts() ORDER BY 1;');
    $sql->execute();
    my $acc = [];
    while ( my $v = $sql->fetchrow() ) {
        push @{$acc}, { accname => $v };
    }
    $sql->finish();

    $self->stash( acc => $acc );

    $dbh->disconnect();
    $self->render();
}

sub delete {
    my $self    = shift;
    my $dbh     = $self->database();
    my $accname = $self->param('accname');
    my $sql     = $dbh->prepare("SELECT public.drop_account(?);");
    if ( $sql->execute($accname) ) {
        $self->msg->info("Account deleted");
        $dbh->commit() if (!$dbh->{AutoCommit});
    }
    else {
        $self->msg->error("Could not delete account");
        $dbh->rollback() if (!$dbh->{AutoCommit});
    }
    $sql->finish();
    $dbh->disconnect();
    $self->redirect_to('accounts_list');
}

sub delrol {
    my $self    = shift;
    my $dbh     = $self->database();
    my $rolname = $self->param('rolname');
    my $accname = $self->param('accname');
    my $sql =
        $dbh->prepare( 'REVOKE "' . $accname . '" FROM "' . $rolname . '"' );
    if ( $sql->execute() ) {
        $self->msg->info("Account removed from user");
        $dbh->commit() if (!$dbh->{AutoCommit});
    }
    else {
        $self->msg->error("Could not remove account from user");
        $dbh->rollback() if (!$dbh->{AutoCommit});
    }
    $sql->finish();
    $dbh->disconnect();
    $self->redirect_to('accounts_edit');
}

sub revokeserver {
    my $self    = shift;
    my $dbh     = $self->database();
    my $idserver = $self->param('idserver');
    my $accname = $self->param('accname');
    my $sql =
        $dbh->prepare( "SELECT rc FROM public.revoke_server(?, ?);");
    if ( $sql->execute($idserver, $accname) ) {
        my $rc = $sql->fetchrow();
        if ( $rc ){
            $self->msg->info("Server revoked");
            $dbh->commit() if (!$dbh->{AutoCommit});
        } else {
            $self->msg->info("Could not revoke server");
            $dbh->rollback() if (!$dbh->{AutoCommit});
        }
    }
    else {
        $self->msg->error("Unknown error");
        $dbh->rollback() if (!$dbh->{AutoCommit});
    }
    $sql->finish();
    $dbh->disconnect();
    $self->redirect_to('accounts_edit');
}

sub edit {
    my $self    = shift;
    my $dbh     = $self->database();
    my $accname = $self->param('accname');
    my $sql;

    $sql = $dbh->prepare(
        "SELECT COUNT(*) FROM public.list_accounts() WHERE accname = ?");
    $sql->execute($accname);
    my $found = ( $sql->fetchrow() == 1);
    $sql->finish();
    if ( !$found ){
        $dbh->disconnect();
        return $self->render_not_found;
    }

    my $method = $self->req->method;
    if ( $method =~ m/^POST$/i ) {

        # process the input data
        my $form_data = $self->req->params->to_hash;

        # Check input values
        my $e = 0;
        if ( !$form_data->{existing_username} =~ m/^\s*$/ ) {

            # Add existing user to account
            $sql =
                $dbh->prepare( 'GRANT "' 
                    . $accname 
                    . '" TO "'
                    . $form_data->{existing_username}
                    . '";' );
            if ( $sql->execute() ) {
                $self->msg->info("User added");
                $dbh->commit() if (!$dbh->{AutoCommit});
            }
            else {
                $self->msg->error("Could not add user");
                $dbh->rollback() if (!$dbh->{AutoCommit});
            }
            $sql->finish();
        }
        elsif ( !$form_data->{new_username} =~ m/^\s*$/ ) {

            # Create new user in this account

            if ( $form_data->{password} =~ m/^\s*$/ ) {
                $self->msg->error("Empty password.");
                $e = 1;
            }
            if ( !$e ) {
                $sql =
                    $dbh->prepare( "SELECT public.create_user(?, ?,'{" . $accname . "}');" );
                if ( $sql->execute($form_data->{new_username},$form_data->{password}) ) {
                    $self->msg->info("User added");
                    $dbh->commit() if (!$dbh->{AutoCommit});
                }
                else {
                    $self->msg->error("Could not add user");
                    $dbh->rollback() if (!$dbh->{AutoCommit});
                }
                $sql->finish();
            }
        }
        elsif ( !$form_data->{existing_hostname} =~ m/^\s*$/ ) {

            # Grant the account to the chosen server
            $sql = $dbh->prepare("SELECT rc FROM public.grant_server(?, ?);");
            if ( $sql->execute($form_data->{existing_hostname},$accname) ){
                my $rc = $sql->fetchrow();
                if ( $rc ){
                    $self->msg->info("Server granted");
                    $dbh->commit() if (!$dbh->{AutoCommit});
                } else {
                    $self->msg->info("Could not grant server");
                    $dbh->rollback() if (!$dbh->{AutoCommit});
                }
            } else {
                $self->msg->info("Unknown error");
                $dbh->rollback() if (!$dbh->{AutoCommit});
            }
        }
    }

    $sql = $dbh->prepare(
        "SELECT useid,rolname FROM list_users(?) ORDER BY 2;");
    $sql->execute($accname);
    my $roles = [];

    while ( my ( $i, $n ) = $sql->fetchrow() ) {
        push @{$roles}, { rolname => $n };
    }
    $sql->finish();

    $sql = $dbh->prepare(
        "SELECT DISTINCT rolname FROM list_users() EXCEPT SELECT rolname FROM list_users(?) ORDER BY 1;"
    );
    $sql->execute($accname);
    my $allroles = [];

    while ( my ($v) = $sql->fetchrow() ) {
        push @{$allroles}, { rolname => $v };
    }
    $sql->finish();

    my $myservers = [];
    my $freeservers = [];
    $sql = $dbh->prepare(
        "SELECT id, hostname, rolname FROM public.list_servers() WHERE rolname = ? OR rolname IS NULL ORDER BY 2;"
    );
    $sql->execute($accname);
    while ( my ($id_server, $hostname, $rolname) = $sql->fetchrow() ) {
        if (scalar $rolname){
            push @{$myservers}, { $id_server => $hostname }
        } else{
            push @{$freeservers}, { $id_server => $hostname };
        }
    }
    $sql->finish();

    $self->stash( roles => $roles, allroles => $allroles, myservers => $myservers, freeservers => $freeservers );

    $dbh->disconnect();
    $self->render();
}

1;
