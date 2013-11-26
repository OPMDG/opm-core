package OPM::Properties;

# This program is open source, licensed under the PostgreSQL Licence.
# For license terms, see the LICENSE file.

use Mojo::Base 'Mojolicious::Plugin';
use Carp;

use Data::Dumper;

has data => sub { { file => '' } };

sub register {
    my ( $self, $app, $conf ) = @_;

    my $file = $conf->{file};

    if ( defined $file ) {
        my $data = $self->data;
        $data->{file} = $file;
        $self->data($data);
    }

    $app->helper( properties => sub { return $self; } );
}

sub load {
    my $self = shift;
    my $file = shift;

    my $data = $self->data;

    if ( defined $file ) {
        $data->{file} = $file;
        $self->data($data);
    }
    else {
        $file = $data->{file};
    }

    my $c = "";
    open( FH, $file ) or croak "Could not open default properties file: $!";
    while (<FH>) {
        chomp;
        $c .= $_ . "\n";
    }
    close(FH);

    my $json = Mojo::JSON->new;
    my $d = $json->decode($c);
    croak "Could not parse default properties file" if !defined $d;

    return $d;
}

sub save {
    my ( $self, $c ) = @_;

    my $data = $self->data;
    my $file = $data->{file};
    my $json = Mojo::JSON->new;

    my $props_json = $json->encode($c);

    open( FH, "> $file" )
        or croak "Could not save default properties file: $!";
    print FH $props_json;
    close(FH);
}

sub validate {
    my ( $self, $input ) = @_;
    my $json = Mojo::JSON->new;

    my %d = %$input;

    $d{'y2axis_title'}       = '' unless defined $d{'y2axis_title'};
    $d{'y2axis_titleAngle'}  = '270' unless defined $d{'y2axis_titleAngle'};
    $d{'y2axis_labelsAngle'} = '0' unless defined $d{'y2axis_labelsAngle'};

    # Process checkboxes: unchecked ones are in the hashref,
    # checked values are 1 and we want true or false.
    foreach my $c (
        qw/xaxis_showLabels yaxis_showLabels y2axis_showLabels bars_stacked
        bars_filled bars_grouped lines_stacked lines_filled points_filled
        pie_filled show_legend/ )
    {
        $d{$c} = ( exists $d{$c} ) ? $json->true : $json->false;
    }

    # Process null fields
    foreach my $k (qw/xaxis_title yaxis_title y2axis_title/) {
        $d{$k} = undef if $d{$k} =~ m/^\s*$/;
    }

    # Process numbers
    foreach my $k (
        qw/points_lineWidth bars_lineWidth y2axis_titleAngle yaxis_labelsAngle points_radius
        y2axis_labelsAngle xaxis_titleAngle xaxis_labelsAngle bars_barWidth pie_lineWidth
        lines_lineWidth yaxis_titleAngle/ )
    {
        if ( $d{$k} !~ m!^[\d\.]+$! ) {
            return undef;
        }

        $d{$k} = $d{$k} + 0;
    }

    # Process lists
    if ( defined $d{colors} ) {
        my @l = split /[\s\,\;]+/, $d{colors};
        $d{colors} = \@l;
    }

    return \%d;
}

sub diff {
    my ( $self, $from, $to ) = @_;

    my %d;
    foreach my $k ( keys %$from ) {
        next if !exists $to->{$k};
        next if ( !defined $from->{$k} && !defined $to->{$k} );
        if ( !defined $from->{$k} || !defined $to->{$k} ) {
            $d{$k} = $to->{$k};
            next;
        }
        $d{$k} = $to->{$k} if $from->{$k} ne $to->{$k};
    }

    return \%d;
}

sub to_plot {
    my ( $self, $props ) = @_;
    my $json = Mojo::JSON->new;

    # This function does (and must do) the same as Grapher.options()
    # in public/js/grapher.js

    my $options = {
        shadowSize => 0,
        title      => $props->{'title'},
        subtitle   => $props->{'subtitle'},
        legend     => { position => 'ne' },
        HtmlText   => $json->false,
        xaxis      => { autoscaleMargin => 5 },
        selection  => { mode => 'x', fps => 30 } };

    foreach my $p ( keys %$props ) {
        if ( $p eq "show_legend" ) {
            $options->{legend}->{show} = $props->{$p};
            next;
        }
        if ( $p =~ m!^(xaxis|yaxis|y2axis|bars|lines|points|pie)_(\w+)$! ) {
            $options->{$1} = {} if !exists $options->{$1};
            if ( $2 eq 'filled' ) {
                $options->{$1}->{fill} = $props->{$p};
            }
            else {
                $options->{$1}->{$2} = $props->{$p};
            }
            next;
        }
        if ( $p eq 'type' ) {
            $options->{ $props->{$p} } = {}
                if !exists $options->{ $props->{$p} };
            $options->{ $props->{$p} }->{show} = $json->true;
            next;
        }
    }

    return $options;
}

1;
