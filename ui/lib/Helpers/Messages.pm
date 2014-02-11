package Helpers::Messages;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';

has msg_lists =>
    sub { { debug => [], info => [], error => [], warning => [] } };


our %Error_class = (
  "debug" => "alert-info",
  "error" => "alert-error",
  "info" => "alert-success"
);


sub register {
    my ( $self, $app ) = @_;

    $app->helper( msg => sub { return $self; } );

    $app->helper(
        display_messages => sub {
            my ($ctrl) = @_;
            my $html;
            foreach my $error_type ('debug', 'error', 'warning', 'info') {
              my $values = $self->msg_lists->{$error_type};
              if(scalar(@$values))
              {
                my $class = $Error_class{$error_type} || '';
                $html .= qq{<div class="alert fade in $class">\n};
                $html .=
                    qq{<button type="button" class="close" data-dismiss="alert">&times;</button>\n};
                $html .= qq{<ul class="unstyled">\n};
                $html .= join( "\n",
                    map { "<li>" . $ctrl->l($_) . "</li>" } @{$values} );
                $html .= qq{</ul></div>};
              }
            }
            # Empty the message list so that it is displayed only once
            $self->msg_lists(
                { debug => [], info => [], error => [], warning => [] } );

            $html = ($html) ? qq{<div id="messages">$html</div>\n} : '';

            return b($html);
            }

    );

    return;
}

sub debug {
    my $self = shift;

    my $messages = $self->msg_lists;
    my @debug    = @{ $messages->{debug} };
    push @debug, @_;
    $messages->{debug} = \@debug;
    $self->msg_lists($messages);
    return;
}

sub info {
    my $self = shift;

    my $messages = $self->msg_lists;
    my @info     = @{ $messages->{info} };
    push @info, @_;
    $messages->{info} = \@info;
    $self->msg_lists($messages);
    return;
}

sub error {
    my $self = shift;

    my $messages = $self->msg_lists;
    my @error    = @{ $messages->{error} };
    push @error, @_;
    $messages->{error} = \@error;
    $self->msg_lists($messages);
    return;
}

sub warning {
    my $self = shift;

    my $messages = $self->msg_lists;
    my @warning  = @{ $messages->{warning} };
    push @warning, @_;
    $messages->{warning} = \@warning;
    $self->msg_lists($messages);
    return;
}

sub save {
    return shift->msg_lists;
}

sub load {
    my $self = shift;
    $self->msg_lists(shift);
}

1;
