package OPM::Users;

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

    my $method = $self->req->method;
    if ( $method =~ m/^POST$/i ) {    # Create a new user
                                      # process the input data
        my $form_data = $self->req->params->to_hash;

        # Check input values
        my $e = 0;
        if ( $form_data->{username} =~ m/^\s*$/ ) {
            $self->msg->error("Empty username.");
            $e = 1;
        }
        if ( $form_data->{accname} =~ m/^\s*$/ ) {
            $self->msg->error("Empty account name.");
            $e = 1;
        }
        if ( $form_data->{password} =~ m/^\s*$/ ) {
            $self->msg->error("Empty password.");
            $e = 1;
        }

        if ( !$e ) {
            $sql =
                $dbh->prepare( "SELECT public.create_user(?, ?, '{" . $form_data->{accname} . "}');");
            if ( $sql->execute($form_data->{username}, $form_data->{password}) ) {
                $self->msg->info("User added");
            }
            else {
                $self->msg->error("Could not add user");
            }
            $sql->finish();
        }
    }

    $sql = $dbh->prepare(
        'SELECT DISTINCT rolname FROM public.list_users() ORDER BY 1;');
    $sql->execute();
    my $roles = [];

    while ( my $v = $sql->fetchrow() ) {
        push @{$roles}, { rolname => $v };
    }
    $sql->finish();

    $sql = $dbh->prepare(
        'SELECT accname FROM public.list_accounts() ORDER BY 1;');
    $sql->execute();
    my $acc = [];

    while ( my $v = $sql->fetchrow() ) {
        push @{$acc}, { accname => $v };
    }
    $sql->finish();

    $self->stash( roles => $roles, acc => $acc );
    $dbh->disconnect();
    $self->render();
}

sub edit {
    my $self    = shift;
    my $dbh     = $self->database();
    my $rolname = $self->param('rolname');
    my $sql;

    $sql = $dbh->prepare(
        "SELECT COUNT(*) > 0 FROM public.list_users() WHERE rolname = ?");
    $sql->execute($rolname);
    my $user_exists = ( $sql->fetchrow() );
    $sql->finish();
    if ( !$user_exists ){
        $dbh->disconnect();
        $self->stash(
            message => 'User not found',
            detail => $self->l('This user does not exists') . ' : "' . $rolname . '"'
        );
        return $self->render_not_found;
    }

    my $method = $self->req->method;
    if ( $method =~ m/^POST$/i ) {    # Add an account to a user
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
                $dbh->prepare( 'SELECT * FROM public.grant_account(?, ?)' );
            if ( $sql->execute( $rolname, $form_data->{accname} ) ) {
                my $rc = $sql->fetchrow();
                if ( $rc) {
                    $self->msg->info("Account added to user");
                } else {
                    $self->msg->error("Could not add account to user");
                }
            }
            else {
                $self->msg->error("Could not add account to user");
            }
            $sql->finish();
        }
    }

    # Select account(s) assigned to user
    $sql = $dbh->prepare(
        "SELECT accname FROM list_users() WHERE rolname = ? AND accname IS NOT NULL ORDER BY 1;"
    );
    $sql->execute($rolname);

    my $acc = [];

    while ( my ($v) = $sql->fetchrow() ) {
        push @{$acc}, { accname => $v };
    }
    $sql->finish();

    # Select account(s) not assigned to user
    $sql = $dbh->prepare(
        "SELECT accname FROM list_accounts() EXCEPT SELECT accname FROM list_users() WHERE rolname = ? ORDER BY 1;"
    );
    $sql->execute($rolname);
    my $allacc = [];

    while ( my ($v) = $sql->fetchrow() ) {
        push @{$allacc}, { accname => $v };
    }
    $sql->finish();

    $self->stash( acc => $acc, allacc => $allacc );
    $dbh->disconnect();
    $self->render();
}

sub delete {
    my $self    = shift;
    my $dbh     = $self->database();
    my $rolname = $self->param('rolname');
    my $sql     = $dbh->prepare("SELECT public.drop_user(?);");
    if ( $sql->execute($rolname) ) {
        $self->msg->info("User deleted");
    }
    else {
        $self->msg->error("Could not delete user");
    }
    $sql->finish();
    $dbh->disconnect();
    $self->redirect_to('users_list');
}

sub delacc {
    my $self    = shift;
    my $dbh     = $self->database();
    my $rolname = $self->param('rolname');
    my $accname = $self->param('accname');
    my $sql =
        $dbh->prepare( 'SELECT * FROM public.revoke_account(?, ?)' );
    if ( $sql->execute($rolname, $accname) ) {
        my $rc = $sql->fetchrow();
        if ( $rc ){
            $self->msg->info("Account removed from user");
        }
        else {
            $self->msg->error("Could not remove account from user");
        }
    }
    else {
        $self->msg->error("Could not remove account from user");
    }
    $sql->finish();
    $dbh->disconnect();
    $self->redirect_to('users_edit');
}

sub login {
    my $self = shift;

    # Do not go through the login process if the user is already in
    if ( $self->perm->is_authd ) {
        return $self->redirect_to('site_home');
    }

    my $method = $self->req->method;
    if ( $method =~ m/^POST$/i ) {

        # process the input data
        my $form_data = $self->req->params->to_hash;

        # Check input values
        my $e = 0;
        if ( $form_data->{username} =~ m/^\s*$/ ) {
            $self->msg->error("Empty username.");
            $e = 1;
        }

        if ( $form_data->{password} =~ m/^\s*$/ ) {
            $self->msg->error("Empty password.");
            $e = 1;
        }
        return $self->render() if ($e);

        my $dbh =
            $self->database( $form_data->{username}, $form_data->{password} );
        if ($dbh) {
            my $sql = $dbh->prepare('SELECT is_admin(current_user);');
            $sql->execute();
            my $admin = $sql->fetchrow();
            $sql->finish();
            $dbh->disconnect();

            # Store information in the session.
            # As the session is only updated at login, if a user is granted
            # admin, he won't have access to specific pages before logging
            # off and on again.
            $self->perm->update_info(
                stay_connected => $form_data->{stay_connected},
                username => $form_data->{username},
                password => $form_data->{password},
                admin    => $admin );

            if ( (defined $self->flash('saved_route')) && (defined $self->flash('stack')) ){
                return $self->redirect_to($self->flash('saved_route'), $self->flash('stack'));
            } else {
                return $self->redirect_to('site_home');
            }
        }
        else {
            $self->msg->error("Wrong username or password.");
            return $self->render();
        }
    }
    $self->flash('saved_route'=> $self->flash('saved_route'));
    $self->flash('stack'=> $self->flash('stack'));
    $self->respond_to(
        json => { json => { error => 'Session expired.', refresh => 1 } },
        html => $self->render()
    );
}

sub profile {
    my $self = shift;
    my $dbh  = $self->database();
    my $sql;

    my $method = $self->req->method;
    if ( $method =~ m/^POST$/i ) {
        # process the input data
        my $form_data = $self->req->params->to_hash;

        if ( !$form_data->{change_password} =~ m/^\s*$/ ){
            # Change password
            my $e = 0;
            if (
                ( $form_data->{current_password} =~ m/^\s*$/ )
                || ( $form_data->{new_password} =~ m/^\s*$/ )
                || ( $form_data->{repeat_password} =~ m/^\s*$/ ) )
            {
                $self->msg->error("Empty password.");
                $e = 1;
            } elsif ( $form_data->{new_password} ne $form_data->{repeat_password} ){
                $self->msg->error("The two passwords does not match");
                $e = 1;
            } elsif ( $form_data->{current_password} ne $self->session->{user_password} ){
                $self->msg->error("Wrong password supplied");
                $e = 1;
            } elsif ( length($form_data->{new_password}) < 6 ){
                $self->msg->error("Password must be longer than 5 characters");
                $e = 1;
            }
            if ( !$e ) {
                my $new_password = $form_data->{new_password};
                $new_password =~ s/'/''/g;
                $sql =
                    $dbh->prepare( 'ALTER ROLE "'
                        . $self->session->{user_username}
                        . '" WITH ENCRYPTED PASSWORD \''
                        . $new_password
                        . '\'' );
                if ( $sql->execute() ) {
                    $self->msg->info("Password changed");
                    $self->session->{user_password} = $form_data->{new_password};
                }
                else {
                    $self->msg->error("Could not change password");
                }
                $sql->finish();
            }
        }
    }

    $sql  = $dbh->prepare(
        'SELECT accname FROM list_users() WHERE rolname = current_user;');
    $sql->execute();
    my $acc = [];
    while ( my $v = $sql->fetchrow() ) {
        push @{$acc}, { acc => $v };
    }
    $sql->finish();
    $dbh->disconnect();
    $self->stash( acc => $acc );
    $self->render();
}

sub logout {
    my $self = shift;

    if ( $self->perm->is_authd ) {
        $self->msg->info("You have logged out.");
    }
    $self->perm->remove_info;
    $self->redirect_to('site_home');
}

sub check_auth {
    my $self = shift;

    # Make the dispatch continue when the user id is found in the session
    if ( $self->perm->is_authd ) {
        return 1;
    }
    $self->flash('saved_route' => $self->current_route);
    $self->flash('stack' => $self->match->stack->[1]);
    $self->redirect_to('users_login');
    return 0;
}

sub check_admin {
    my $self = shift;

    # Make the dispatch continue only if the user has admin privileges
    if ( $self->perm->is_admin ) {
        return 1;
    }

    # When the user has no privileges, do not redirect, send 401 unauthorized instead
    $self->render( 'unauthorized', status => 401 );

    return 0;
}

1;
