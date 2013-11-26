package OPM::Lang;

# This program is open source, licensed under the PostgreSQL Licence.
# For license terms, see the LICENSE file.

use Mojo::Base 'Mojolicious::Controller';

sub set {
    my $self = shift;
    my $code = $self->param('code');
    $self->session( user_lang => $code );
    $self->redirect_to('/');
}

1;
