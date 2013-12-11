/**
 * Grapher javascript
 *
 * This program is open source, licensed under the PostgreSQL License.
 * For license terms, see the LICENSE file.
 *
 * Copyright (C) 2012-2013: Open PostgreSQL Monitoring Development Group
**/

(function($) {

    var Grapher = function (element, options) {
        this.config = options;
        this.$element = $(element);
        this.legend_box = this.config.legend_box ?
            this.config.legend_box
            : $('<div class="legend" />');

        this.$element.append('<div class="plot">');
        this.legend_box
            .data('id-graph', this.$element.attr('id-graph'));

        if (! this.config.legend_box)
            this.$element.append(this.legend_box);

        this.default_props = {
            autoscale: true,
            bars: {
              barWidth: 1,
              filled: true,
              gropued: false,
              lineWidth: 2,
              stacked: false
            },
            HtmlText: false,
            legend: {
              position: 'ne',
              show: false
            },
            lines: {
              filled: true,
              lineWidth: 0.5,
              stacked: false
            },
            mouse: {
                 track: true,
                 sensibility: 5,
                 trackFormatter: function (o) {
                     d = new Date(new Number(o.x));
                     return d.toUTCString() +"<br />"+ o.series.label +' = '+ o.series.data[o.index][1];
                 }
            },
            pie: {
              filled: true,
              lineWidth: 2
            },
            points: {
              filled: true,
              lineWidth: 2,
              radius: 3
            },
            selection: {
                mode : 'x',
                fps : 30
            },
            shadowSize: 0,
            type: 'line',
            xaxis: {
                autoscale: false,
                autoscaleMargin: 5,
                labelsAngle: 0,
                mode: 'time',
                showLabels: true,
                timeFormat: '%d/%m/%y %H:%M:%S',
                titleAngle: 0
            },
            yaxis: {
                autoscale: true,
                autoscaleMargin: 5,
                labelsAngle: 0,
                showLabels: true,
                titleAngle: 90,
                tickFormatter: function (val, axis) {
                    var unit = this.unit;

                    if (unit == null) unit = '';
                    switch ( unit ) {
                        case 'B':
                            if (val > (1024*1024*1024*1024*1024))
                                return (val / (1024*1024*1024*1024*1024)).toFixed(2) + " Pi" + unit;
                            if (val > (1024*1024*1024*1024))
                                return (val / (1024*1024*1024*1024)).toFixed(2) + " Ti" + unit;
                            if (val > (1024*1024*1024))
                                return (val / (1024*1024*1024)).toFixed(2) + " Gi" + unit;
                            if (val > (1024*1024))
                                return (val / (1024*1024)).toFixed(2) + " Mi" + unit;
                            if (val > 1024)
                                return (val / 1024).toFixed(2) + " ki" + unit;
                            return val + " " + unit;
                        break;

                        case 's':
                            var minute = 60;
                            var hour = 60 * minute;
                            var day = 24 * hour;
                            var year = 365 * day;
                            function formatyear(t){
                                if (t < year)
                                    return formatday(t);
                                else
                                    return Math.floor(t/year)+'y '+formatday(t%year);
                            }
                            function formatday(t){
                                if (t < day)
                                    return formathour(t);
                                else
                                    return Math.floor(t/day)+'d '+formathour(t%day);
                            }
                            function formathour(t){
                                if (t < hour)
                                    return formatminute(t);
                                else
                                    return Math.floor(t/hour)+'h '+formatminute(t%hour);
                            }
                            function formatminute(t){
                                if (t < minute)
                                    return t+'s';
                                else
                                    return Math.floor(t/minute)+'m '+(t%minute)+'s';
                            }
                            return formatyear(val);
                        break;

                        default:
                            return val + " " + unit;
                        break;
                    }
                }
            }
        };
    }

    Grapher.prototype = {

        constructor: Grapher,

        html_error: function (message) {
            if (typeof message == 'undefined') message = '';

            return '<div class="alert alert-error">'+
                '<button type="button" class="close" data-dismiss="alert">&times;</button>'+
                '<strong>Error:</strong> '+ message +
                '</div>';
        },

        fetch_data: function (url, fromDate, toDate) {

            var grapher = this,
                post_data;

            if (fromDate == null)
                fromDate = this.config.from;

            if (toDate == null)
                toDate = this.config.to;

            post_data = {
                id: this.config.id,
                from: fromDate,
                to: toDate
            };

            var a = $.ajax(url, {
                async: false,
                cache: false,
                type: 'post',
                url: url,
                dataType: 'json',
                data: post_data,
                success: function (r) {
                    grapher.fetched = r;
                    if (! r.error)
                        grapher.fetched.properties = $.extend(true,
                            grapher.default_props,
                            grapher.fetched.properties || {}
                        );
                }
            });
        },

        draw: function () {
            var $plot   = this.$element.find('.plot'),
                $legend = this.legend_box
                inactiveSeries = null;

            // Empty the graph to draw it from scratch
            $legend.empty();

            // Remember active series if we already have some
            if (this.fetched && this.fetched.series.length) {
                inactiveSeries = new Array();
                $.map(this.fetched.series, function (s) {
                    if (s.hide) inactiveSeries.push(s.label);
                });
            }

            // Fetch to data to plot
            this.fetch_data(this.config['url']);

            if (this.fetched.error != null) {
                $plot.append(this.html_error(this.fetched.error));
                return;
            }

            if (inactiveSeries !== null) {
                $.map(this.fetched.series, function (s) {
                    if (inactiveSeries.indexOf(s.label) !== -1)
                        s.hide = true;
                });
            }

            this.refresh();
            this.drawLegend();
        },

        refresh: function () {
            var properties = this.fetched.properties,
                series     = this.fetched.series,
                container  = this.$element.find('.plot').get(0);

            this.$element.find('.plot').unbind().empty();

            // Draw the graph
            this.flotr = Flotr.draw(container, series, properties);
        },

        _activateSerie: function($e) {
            with ($e) {
                find('.flotr-legend-color-box')
                    .css('opacity', 0.9);
                find('label')
                    .removeClass('deactivated');
            }
        },

        _deactivateSerie: function($e) {
            with ($e) {
                find('.flotr-legend-color-box')
                    .css('opacity', 0.1);
                find('label')
                    .addClass('deactivated');
            }
        },

        drawLegend: function() {

            var $legend    = this.legend_box,
                legend_opt = this.flotr.legend.options,
                series     = this.flotr.series,
                i, label, color,
                itemCount  = $.grep(series, function (e) {
                        return (e.label && !e.hide) }
                    ).length;

            if (itemCount) {
                for(i = 0; i < series.length; ++i) {
                    if(!series[i].label) continue;

                    var s = series[i];

                    label = legend_opt.labelFormatter(s.label);
                    color = ((s.bars && s.bars.show && s.bars.fillColor && s.bars.fill) ? s.bars.fillColor : s.color);

                    var $cell = $(
                        '<div class="flotr-legend-color-box" />'
                    )
                        .css({
                            'margin' : '0 10px 0 0',
                            'float'  : 'left',
                            'border' : '1px solid '+ legend_opt.labelBoxBorderColor,
                            'width'  : '1.4em',
                            'height' : '1.2em',
                            'background-color': color
                        })
                        .attr('id', 'legendcolor'+i)
                        .add('<label>'+ label +'</label>');

                    var $label = $('<div class="label-'+ i +'" />').prepend($cell)
                        .data('i', i)
                        .click(function () {
                            var $this   = $(this),
                                grapher = $('[id-graph='+ $this.parent().data('id-graph') +']')
                                    .grapher(),
                                s       = grapher.fetched.series[$this.data('i')];

                            if ( (s.hide = ! s.hide) )
                                grapher._deactivateSerie($this);
                            else
                                grapher._activateSerie($this);

                            grapher.refresh();
                        })
                        .appendTo($legend);

                    if (s.hide)
                        this._deactivateSerie( $label );
                }

                $legend.css({
                    height: this.flotr.canvasHeight
                });
            }
        },

        zoom: function (tsfrom, tsto) {
            var i;

            if (!tsfrom || !tsto) return false;

            $.extend(this.config, {
                from: tsfrom,
                to: tsto
            });

            this.draw();

            return true;
        },

        export: function() {
            var legend_shown = this.fetched.properties.legend.show;
            if (!legend_shown) {
                this.fetched.properties.legend.show = true;
                this.refresh();
            }
            this.flotr.download.saveImage('png', null, null, false);
            if (!legend_shown) {
                this.fetched.properties.legend.show = legend_shown;
                this.refresh();
            }
        },

        activateSeries: function () {
            var series     = this.fetched.series,
                i;

            for(i = 0; i < series.length; ++i)
                series[i].hide = false;

            this._activateSerie( this.legend_box.find('> div') );

            this.refresh();
        },

        deactivateSeries: function () {
            var series     = this.fetched.series,
                i;

            for(i = 0; i < series.length; ++i)
                series[i].hide = true;

            this._deactivateSerie( this.legend_box.find('> div') );

            this.refresh();
        },

        invertActivatedSeries: function () {
            var series  = this.fetched.series,
                $legend = this.legend_box,
                $hidden = $legend.find('label.deactivated').parent(),
                $showed = $legend.find('label:not(.deactivated)').parent(),
                i;

            for(i = 0; i < series.length; ++i)
                series[i].hide = ! series[i].hide;

            if ($showed.length) this._deactivateSerie($showed);
            if ($hidden.length) this._activateSerie($hidden);

            this.refresh();
        }
    };

    // Plugin definition
    $.fn.grapher = function (param) {
        if (typeof param == 'object') {
            return this.each(function () {

                var $this = $(this),
                    grapher = $this.data('grapher');

                // if no grapher object is already registred on this tag, add it
                if (grapher) return;

                var options = $.extend({}, {
                        properties: null,
                        id:         null,
                        to:         null,
                        from:       null,
                        url:        null
                    },
                    param
                );

                options.id = $this.attr('id-graph');

                if (options.id === undefined) return;

                $this.data('grapher', (grapher = new Grapher(this, options)));
                $this.data('zooms', new Array());

                Flotr.EventAdapter.observe($this.find('.plot').get(0), 'flotr:select', function (sel, g) {
                    $this.data('zooms').push([
                        grapher.config.from,
                        grapher.config.to
                    ]);

                    grapher.zoom(Math.round(sel.x1), Math.round(sel.x2));

                });

                Flotr.EventAdapter.observe($this.find('.plot').get(0), 'flotr:click', function () {
                    var zo = $this.data('zooms').pop();
                    if (zo)
                        grapher.zoom(zo[0], zo[1]);
                });
            });
        }
        else if (! param ) {
            return $(this).data('grapher');
        }
    }

})(jQuery);
