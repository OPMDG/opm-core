package OPM::Accounts;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;
use Digest::SHA qw(sha256_hex);

sub list {
    my $self       = shift;
    my $method     = $self->req->method;
    my $validation = $self->validation;
    my $sql;

    if ( $method eq 'POST' && $validation->has_data ) {{
        my $form_data;

        $validation->required('accname');
        $self->validation_error($validation);
        last if $validation->has_error;

        $form_data = $validation->output;

        if ( $self->dbsubs->create_account( $form_data->{accname} ) ) {
            $self->msg->info("Account created");
            return $self->redirect_post('accounts_list');
        }

        $self->msg->error("Could not create account");
    }}

    $sql = $self->prepare('SELECT accname
        FROM public.list_accounts()
        ORDER BY 1
    ');
    $sql->execute();

    $self->stash( acc => $sql->fetchall_arrayref( {} ) );

    return $self->render('accounts/list');
}

sub delete {
    my $self    = shift;
    # TODO: ensure that this is only accessible via get (see issue #59)
    my $accname = $self->param('accname');

    if ( $self->dbsubs->drop_account($accname) ) {
        $self->msg->info("Account deleted");
    }
    else {
        $self->msg->error("Could not delete account");
    }

    return $self->redirect_post('accounts_list');
}

sub delrol {
    my $self    = shift;
    # TODO: ensure that this is only accessible via get (see issue #59)
    my $rolname = $self->param('rolname');
    my $accname = $self->param('accname');

    if ( $self->dbsubs->revoke_account( $rolname, $accname ) ) {
        $self->msg->info("Account removed from user");
    }
    else {
        $self->msg->error("Could not remove account from user");
    }

    return $self->redirect_post('accounts_edit');
}

sub revokeserver {
    my $self     = shift;
    # TODO: ensure that this is only accessible via get (see issue #59)
    my $idserver = $self->param('idserver');
    my $accname  = $self->param('accname');

    if ( $self->dbsubs->revoke_server( $idserver, $accname ) ) {
        $self->msg->info("Server revoked");
    }
    else {
        $self->msg->info("Could not revoke server");
    }

    return $self->redirect_to('accounts_edit');
}

sub _is_account {
    my ( $self, $accname ) = @_;
    my $sql = $self->prepare('SELECT COUNT(*)
        FROM public.list_accounts()
        WHERE accname = ?
    ');

    $sql->execute($accname);

    return $sql->fetchrow() == 1;
}

sub edit {
    my $self        = shift;
    my $accname     = $self->param('accname');
    my $myservers   = [];
    my $freeservers = [];
    my $rc;
    my $sql;
    my $roles;
    my $allroles;

    # TODO: find a way to raise a NotFound exception
    # from another subroutine.
    return $self->render_not_found unless $self->_is_account($accname);

    $sql = $self->prepare('SELECT useid, rolname
        FROM list_users(?)
        ORDER BY 2
    ');
    $sql->execute($accname);
    $roles = $sql->fetchall_arrayref( {} );

    $sql = $self->prepare('SELECT DISTINCT rolname
        FROM list_users()
        EXCEPT SELECT rolname
        FROM list_users(?)
        ORDER BY 1
    ');
    $sql->execute($accname);
    $allroles = $sql->fetchall_arrayref( {} );

    $sql = $self->prepare('SELECT id, hostname, rolname
        FROM public.list_servers()
        WHERE rolname = ?
            OR rolname IS NULL
        ORDER BY 2
    ');
    $sql->execute($accname);

    while ( my ( $id_server, $hostname, $rolname ) = $sql->fetchrow() ) {
        if ( scalar $rolname ) {
            push @{$myservers}, { $id_server => $hostname };
        }
        else {
            push @{$freeservers}, { $id_server => $hostname };
        }
    }

    $self->stash(
        roles       => $roles,
        allroles    => $allroles,
        myservers   => $myservers,
        freeservers => $freeservers
    );

    return $self->render('accounts/edit');
}

sub add_user {
    my $self    = shift;
    my $method  = $self->req->method;
    my $accname = $self->param('accname');

    return $self->render_not_found unless $self->_is_account($accname);

    if ( $method eq 'POST' ) {{
        my $validation = $self->validation;

        $validation->required('existing_username');
        $self->validation_error($validation);
        last if $validation->has_error;

        if ($self->dbsubs->grant_account(
            $validation->output->{existing_username}, $accname
        )) {
            $self->msg->info("User added");
            return $self->redirect_post('accounts_edit');
        }

        $self->msg->error("Could not add user");
    }}
    return $self->edit;
}

sub new_user {
    my $self    = shift;
    my $method  = $self->req->method;
    my $accname = $self->param('accname');

    return $self->render_not_found unless $self->_is_account($accname);

    if ( $method eq 'POST' ) {{
        my $validation = $self->validation;

        $validation->required('new_username');
        $validation->required('password')->size( 5, 64 );
        $self->validation_error($validation);
        last if $validation->has_error;

        if ($self->dbsubs->create_user(
            $validation->output->{new_username},
            $validation->output->{password},
            [ $accname ]
        )) {
            $self->msg->info("User added");
            return $self->redirect_post('accounts_edit');
        }

        $self->msg->error("Could not add user");
    }}
    return $self->edit;
}

sub add_server {
    my $self    = shift;
    my $method  = $self->req->method;
    my $accname = $self->param('accname');

    return $self->render_not_found unless $self->_is_account($accname);

    if ( $method eq 'POST' ) {{
        my $validation = $self->validation;

        $validation->required('existing_hostname');
        $self->validation_error($validation);
        last if $validation->has_error;

        if ($self->dbsubs->grant_server(
            $validation->output->{existing_hostname},
            $accname
        )) {
            $self->msg->info("Server granted");
            return $self->redirect_post('accounts_edit');
        }

        $self->msg->info("Could not grant server");
    }}

    return $self->edit;
}

1;
