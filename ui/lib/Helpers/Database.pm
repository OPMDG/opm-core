package Helpers::Database;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2018: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Plugin';

use Carp;
use DBI;
use Helpers::Database::ProcWrapper;
use Helpers::Database::Sth;

has conninfo => sub { [] };

sub register {
    my ( $self, $app, $dbconf ) = @_;

    # data source name
    my $dsn = "dbi:Pg:";
    $dsn .= 'database=' . $dbconf->{dbname} || lc $ENV{MOJO_APP};
    $dsn .= ';host='    . $dbconf->{host} if $dbconf->{host};
    $dsn .= ';port='    . $dbconf->{port} if $dbconf->{port};

    # Save connection parameters
    $self->conninfo($dsn);

    # Force AutoCommit to be able to handle transactions if needed.
    # and avoid unnecessary commit/rollback.
    $dbconf->{options}->{AutoCommit} = 1;
    # Force UTF-8
    $dbconf->{options}->{pg_enable_utf8} = 1;

    # Register a helper that give the database handle
    $app->helper( database => sub {
        my ( $ctrl ) = @_;
        my $dbh;

        $dbh = $ctrl->stash->{'dbh'};

        return $dbh if defined $dbh;

        # Return a new database connection handle
        $dbh = DBI->connect( $self->conninfo,
            $dbconf->{user}, $dbconf->{password},
            $dbconf->{options} || {}
        );

        if($dbh) {
            $ctrl->stash->{'dbh'} = $dbh;

            $ctrl->proc_wrapper->set_opm_session($ctrl->session('user_username'))
                if defined $ctrl->session('user_username');

            return $dbh;
        }
        else {
            $ctrl->stash->{'err_msg'} = "Could not connect to the database";
            $ctrl->stash->{'err_det'} = DBI->errstr;
        }

        $ctrl->redirect_post('site_home');

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

        $dbh->disconnect() if $dbh;
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
