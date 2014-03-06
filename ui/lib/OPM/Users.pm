package OPM::Users;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Controller';
use Helpers::Database;

sub list {
    my $self = shift;
    my $sql;
    my $roles;
    my $acc;

    $sql = $self->prepare('SELECT DISTINCT rolname
        FROM public.list_users()
        ORDER BY 1
    ');
    $sql->execute();
    $roles = $sql->fetchall_arrayref({});

    $sql = $self->prepare('SELECT accname
        FROM public.list_accounts()
        ORDER BY 1
    ');
    $sql->execute();
    $acc = $sql->fetchall_arrayref({});

    return $self->render('users/list',
        roles => $roles,
        acc => $acc
    );
}

sub create {
    my $self       = shift;
    my $method     = $self->req->method;
    my $validation = $self->validation;
    my $form_data;
    my $created;

    if (!($method eq 'POST' && $validation->has_data)) {
        return $self->list;
    }

    # Create a new user

    $form_data = $self->req->params->to_hash;

    # process the input data
    $validation->required('username');
    $validation->required('accname');
    $validation->required('password')->size(5, 64);
    $self->validation_error($validation);

    return $self->list if $validation->has_error;

    $created = $self->proc_wrapper->create_user(
        $form_data->{username},
        $form_data->{password},
        [ $form_data->{accname} ]
    );
    unless( $created ) {
        $self->msg->error("Could not add user");
        return $self->list;
    }

    $self->msg->info("User added");

    return $self->redirect_post('users_list');
}

sub edit {
    my $self    = shift;
    my $rolname = $self->param('rolname');
    my $sql;
    my $user_exists;
    my $method;
    my $validation;
    my $acc;
    my $allacc;

    $sql = $self->prepare('SELECT COUNT(*) > 0
        FROM public.list_users()
        WHERE rolname = ?
    ');
    $sql->execute($rolname);
    $user_exists = $sql->fetchrow();

    unless ( $user_exists ) {
        $self->stash(
            message => 'User not found',
            detail  => $self->l('This user does not exists') . qq{ : "$rolname"}
        );
        return $self->render_not_found;
    }

    $method     = $self->req->method;
    $validation = $self->validation;

    if ( $method eq 'POST' && $validation->has_data ) {
        $validation->required('accname');
        $self->validation_error($validation);

        if( $validation->is_valid ) {
            my $granted = $self->proc_wrapper->grant_account(
                $rolname, $validation->output->{accname}
            );
            
            if( $granted ) {
                $self->msg->info("Account added to user");
            }
            else {
                $self->msg->error("Could not add account to user");
            }
      }
    }

    # Select account(s) assigned to user
    $sql = $self->prepare('SELECT accname
        FROM list_users()
        WHERE rolname = ?
            AND accname IS NOT NULL
        ORDER BY 1
    ');
    $sql->execute($rolname);
    $acc = $sql->fetchall_arrayref({});

    # Select account(s) not assigned to user
    $sql = $self->prepare('SELECT accname
        FROM list_accounts()
        EXCEPT SELECT accname
        FROM list_users()
        WHERE rolname = ?
        ORDER BY 1
    ');
    $sql->execute($rolname);
    $allacc = $sql->fetchall_arrayref({});

    return $self->render('users/edit',
        acc => $acc,
        allacc => $allacc
    );
}

sub delete {
    my $self    = shift;
    my $rolname = $self->param('rolname');

    if ( $self->proc_wrapper->drop_user( $rolname ) ) {
        $self->msg->info("User deleted");
    }
    else {
        $self->msg->error("Could not delete user");
    }

    return $self->redirect_post('users_list');
}

sub delacc {
    my $self    = shift;
    my $rolname = $self->param('rolname');
    my $accname = $self->param('accname');

    if ( $self->proc_wrapper->revoke_account($rolname, $accname) ) {
        $self->msg->info("Account removed from user");
    }
    else {
      $self->msg->error("Could not remove account from user");
    }

    return $self->redirect_post('users_edit');
}

sub login {
    my $self = shift;
    my $method;

    # Do not go through the login process if the user is already in
    if ( $self->perm->is_authd ) {
        return $self->redirect_post('site_home');
    }

    $method = $self->req->method;

    if ( $method eq 'POST' ) {
        # process the input data
        my $validation = $self->validation;
        my $form_data;
        my $admin;
        my $dbh;

        $validation->required('username');
        $validation->required('password');
        $self->validation_error($validation);
        return $self->render() if $validation->has_error;

        $form_data = $validation->output;
        $dbh = $self->database( $form_data->{username}, $form_data->{password} );

        unless ($dbh) {
            $self->msg->error("Wrong username or password.");
            return $self->render();
        }

        $self->perm->update_info(
            stay_connected => $form_data->{stay_connected},
            username       => $form_data->{username},
            password       => $form_data->{password}
        );

        $admin = $self->proc_wrapper->is_admin( $form_data->{username} );

        # Store information in the session.
        # As the session is only updated at login, if a user is granted
        # admin, he won't have access to specific pages before logging
        # off and on again.
        $self->perm->update_info( admin => $admin );

        if ( defined $self->flash('saved_route')
            and defined $self->flash('stack')
        ) {
            return $self->redirect_post($self->flash('saved_route'), $self->flash('stack'));
        }

        return $self->redirect_post('site_home');
    }

    $self->flash('saved_route'=> $self->flash('saved_route'));
    $self->flash('stack'=> $self->flash('stack'));
    return $self->render();
}


sub change_password {
    my $self = shift;
    my $validation;
    my $new_password;

    return $self->render_not_found unless $self->req->method eq 'POST';

    # process the input data
    $validation = $self->validation;
    $validation->required('current_password')
        ->in($self->session->{user_password});
    $validation->required('new_password')->size(5, 64);
    $validation->required('repeat_password')->equal_to('new_password');
    $self->validation_error($validation);

    return $self->profile if $validation->has_error;

    $new_password = $validation->output->{new_password};
    if( $self->proc_wrapper->update_current_user($new_password) ) {
        $self->msg->info("Password changed");
        $self->session->{user_password} = $validation->output->{new_password};
        return $self->redirect_post('users_profile');
    }

    $self->msg->error("Could not change password");
    return $self->profile;
}

sub profile {
    my $self = shift;
    my $sql  = $self->prepare('SELECT accname AS acc
        FROM list_users()
        WHERE rolname = current_user
    ');

    $sql->execute();

    return $self->render('users/profile',
        acc => $sql->fetchall_arrayref({})
    );
}

sub logout {
    my $self = shift;

    if ( $self->perm->is_authd ) {
        $self->msg->info("You have logged out.");
    }

    $self->perm->remove_info;
    return $self->redirect_post('site_home');
}

sub check_auth {
    my $self = shift;

    # Make the dispatch continue when the user id is found in the session
    if ( $self->perm->is_authd ) {
        return 1;
    }

    $self->flash('saved_route' => $self->current_route);
    $self->flash('stack' => $self->match->stack->[1]);

    if ( $self->req->headers->accept =~ m@application/json@ ) {
        $self->msg->error('Session expired.');
        $self->respond_to( json => {
            json => {
                'error' => 'Session expired.',
                'redirect' => 1
            }
        });
        return 0;
    }

    $self->redirect_post('users_login');
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

sub about {
    my $self = shift;
    my $sql;

    $sql = $self->prepare(q{SELECT name, version
        FROM pg_available_extension_versions
        WHERE installed
            AND ('opm_core' = ANY(requires)
                OR name = 'opm_core'
            )
        ORDER BY name}
    );

    $sql->execute();

    $self->stash( exn => $sql->fetchall_arrayref({}) );

    return $self->render();
}

1;
