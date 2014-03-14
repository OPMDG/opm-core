package OPM::Plugin;
use Mojo::Base 'Mojolicious::Plugin';
use Carp 'croak';

sub register {
    my $self = shift;
    return $self;
}

sub register_routes {
    croak 'Method "register_routes" not implemented by subclass';
}

sub links {
    my %links;
    return \%links;
}

sub AUTOLOAD {
    my $self = shift,
        my ( $package, $method ) = split /::(\w+)$/, our $AUTOLOAD;
    if ( $method =~ /^links_/ ) {
        return $self->can($method) ? $self->$method(@_) : [];
    }
    croak "Method $method does not exist";
}

sub DESTROY {
}

return 1;
