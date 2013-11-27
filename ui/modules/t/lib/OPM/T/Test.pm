package OPM::T::Test;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2013: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Controller';

sub start {
    my $self = shift;
    return $self->redirect_to('/selenium-lib/core/TestRunner.html?test=%2Ft%2Flist');
}

sub list {
    my $self = shift;

    opendir my($dh), 'modules/t/public/tests/src/';
    my @allfiles = readdir $dh;
    closedir $dh;

    my $files = [];
    foreach my $f (@allfiles){
        push @{$files}, $f if ( substr($f,0,1)  ne '.' and substr($f,-5) eq '.html' );
    }

    $self->stash( files => $files );
    $self->render();
}

1;
