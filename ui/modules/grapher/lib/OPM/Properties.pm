package OPM::Properties;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2013: Open PostgreSQL Monitoring Development Group

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

sub validate {
    my ( $self, $input ) = @_;
    my $json = Mojo::JSON->new;

    my %d = %$input;

    # Remove empty values to use library/grapher defaults
    foreach my $k (
        qw/xaxis_timeFormat points_lineWidth bars_lineWidth pie_lineWidth
        lines_lineWidth xaxis_titleAngle xaxis_labelsAngle yaxis_titleAngle
        yaxis_labelsAngle points_radius bars_barWidth/ )
    {
        delete $d{$k} if $d{$k} =~ m/^\s*$/;
    }

    # Process checkboxes: unchecked ones are in the hashref,
    # checked values are 1 and we want true or false.
    foreach my $c (
        qw/yaxis_showLabels bars_stacked
        bars_filled bars_grouped lines_stacked lines_filled points_filled
        pie_filled show_legend/ )
    {
        $d{$c} = ( exists $d{$c} ) ? $json->true : $json->false;
    }

    # Process null fields
    foreach my $k (qw/xaxis_title yaxis_title/) {
        $d{$k} = undef if $d{$k} =~ m/^\s*$/;
    }

    # Process numbers
    foreach my $k (
        qw/points_lineWidth bars_lineWidth yaxis_labelsAngle points_radius
        xaxis_titleAngle xaxis_labelsAngle bars_barWidth pie_lineWidth
        lines_lineWidth yaxis_titleAngle/ )
    {
        if ( ( exists $d{$k} ) && ( $d{$k} =~ m!^[\d\.]+$! ) ) {
        $d{$k} = $d{$k} + 0;
        }
    }

    # Process lists
    if ( defined $d{colors} ) {
        my @l = split /[\s\,\;]+/, $d{colors};
        $d{colors} = \@l;
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
