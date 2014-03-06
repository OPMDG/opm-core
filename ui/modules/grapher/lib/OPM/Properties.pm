package OPM::Properties;

# This program is open source, licensed under the PostgreSQL License.
# For license terms, see the LICENSE file.
#
# Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group

use Mojo::Base 'Mojolicious::Plugin';
use Carp;

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

    my %d;

    # Remove empty values to use library/grapher defaults
    foreach my $k ( qw{
        xaxis_timeFormat xaxis_title yaxis_title xaxis_mode
        type
    }) {
        next unless $input->{$k} and $input->{$k} !~ m/^\s*$/;
        $d{$k} = $input->{$k};
    }

    # Process checkboxes: unchecked ones are in the hashref,
    # checked values are 1 and we want true or false.
    foreach my $c ( qw{
        bars_stacked bars_filled bars_grouped lines_stacked
        lines_filled points_filled pie_filled show_legend
    }) {
        $d{$c} = ( exists $input->{$c} ) ? $json->true : $json->false;
    }

    # Process numbers
    foreach my $k ( qw{
        bars_lineWidth bars_barWidth lines_lineWidth pie_lineWidth
        points_lineWidth points_radius xaxis_labelsAngle
        xaxis_titleAngle yaxis_labelsAngle yaxis_titleAngle
    }) {
        next unless exists $input->{$k}
            and $input->{$k} =~ m/^[\d\.]+$/;

        $d{$k} = $input->{$k} + 0;
    }

    # Process lists
    if ( defined $input->{'colors'} ) {
        my @l = split /[\s\,\;]+/, $input->{'colors'};
        $d{'colors'} = \@l;
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
