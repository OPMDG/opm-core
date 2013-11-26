package OPM::Grapher::Properties;

use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;

sub defaults {
    my $self = shift;

    my $properties = $self->properties->load;

    # Form data
    my $method = $self->req->method;
    if ( $method =~ m/^POST$/i ) {

        # process the input data
        my $form = $self->req->params->to_hash;

        # Action depends on the name of the button pressed
        if ( exists $form->{cancel} ) {
            return $self->redirect_to('graphs_list');
        }

        if ( exists $form->{save} ) {
            delete $form->{save};

            my $props = $self->properties->validate($form);
            if ( !defined $props ) {
                $self->msg->error("Bad input, please double check the form");
                return $self->render;
            }

            say Dumper( $self->properties->diff( $properties, $props ) );

            $self->properties->save($props);
            $self->msg->info("Default properties updated");
            $properties = $self->properties->load;
        }
    }

    foreach my $p ( keys %$properties ) {
        $self->param( $p, $properties->{$p} );
    }

    $self->render;
}

1;
