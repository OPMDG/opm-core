package Helpers::Database;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Plugin';

use Carp;
use DBI;
use Helpers::Database::ProcWrapper;
use Helpers::Database::Sth;


has conninfo => sub { [] };

sub register {
    my ( $self, $app, $config ) = @_;

    # data source name
    my $dsn = $config->{dsn};

    # Check if we have a split dsn with fallback on defaults
    unless ($dsn) {
        my $database = $config->{database} || lc $ENV{MOJO_APP};
        my $dsn = "dbi:Pg:database=" . $database;
        $dsn .= ';host=' . $config->{host} if $config->{host};
        $dsn .= ';port=' . $config->{port} if $config->{port};
    }

    # Save connection parameters
    $self->conninfo($dsn);

    # Force AutoCommit to be able to handle transactions if needed.
    # and avoid unnecessary commit/rollback.
    $config->{options}->{AutoCommit} = 1;


    # Register a helper that give the database handle
    $app->helper( database => sub {
        my ( $ctrl, $username, $password ) = @_;
        my $dbh;

        if ( ( !defined($username) ) or ( !defined($password) ) ) {
            $username = $ctrl->session('user_username');
            $password = $ctrl->session('user_password');
        }

        return unless defined $username;

        $dbh = $ctrl->stash->{'dbh'}->{$username};

        return $dbh if defined $dbh;

        # Return a new database connection handle
        $dbh = DBI->connect( $self->conninfo,
            $username, $password,
            $config->{options} || {}
        );

        if($dbh && $self->db_sub_one($dbh, 'is_user', $username)) {
          $ctrl->stash('dbh')->{$username} = $dbh;
          return $dbh;
        }

        # If the user is the current logged in user and is not valid,
        # disconnect
        if($username eq $ctrl->session('user_username')) {
          $ctrl->perm->remove_info;
          $ctrl->redirect_post('site_home');
        }

        return;
    });

    $app->helper( prepare => sub {
        my ( $ctrl, $stmt ) = @_;
        return Helpers::Database::Sth->new(
            sth => $ctrl->database->prepare($stmt)
        );
    });

    $app->helper( proc_wrapper => sub {
        my $ctrl = shift;
        my %args = (
          schema => 'public',
          @_
        );

        return Helpers::Database::ProcWrapper->new(
            db         => $self,
            connection => $ctrl->database(),
            schema     => $args{schema}
        );
    });

    # Register a hook that will trash the connection if needed.
    $app->hook( after_dispatch => sub {
        my $self = shift;
        my $dbh = $self->stash->{'dbh'};
        while( (my $key, my $value) = each %{$dbh} ){
          $value->disconnect() if $dbh;
          delete $dbh->{$key};
        }
    });

    # Register a helper that executes a database functions, and returns a single
    # result.
    $app->helper(db_sub_one => \&db_sub_one);
    return;
}

sub db_sub_one {
    my ($self, $dbh) = (shift, shift);
    my $stmt = _db_sub($dbh, @_);
    my $result = $stmt->fetchrow();
    $stmt->finish();
    return $result;
};


sub _function_call {
  my $fnname = shift;
  my $fn_args = join(",", map { "?" } @_);
  return "$fnname($fn_args)";
}


sub _db_sub {
    my ($dbh, $fnname) = (shift, shift);
    my $fncall = _function_call($fnname, @_);
    my $stmt = $dbh->prepare("SELECT $fncall;");
    $stmt->execute(@_);
    return $stmt;
}

1;
