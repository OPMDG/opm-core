/**
 * Javascript for page show.html.ep
 *
 * This program is open source, licensed under the PostgreSQL License.
 * For license terms, see the LICENSE file.
 *
 * Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group
 **/
$(document).ready(function () {
  /* bind the datetimepicker to the date fields */
  $('.datepick').datetimepicker({
    format: 'dd/MM/yyyy hh:mm:ss'
  });

  $('[data-graphid]').each(function () {
    var $this = $(this),
        $plot_box = $this.find('[data-graphrole="plot"]'),
        $legend_box = $this.find('[data-graphrole="legend"]'),
        $grapher;
    $plot_box.grapher({
      url: $this.attr('data-graphurl'),
      id: $this.attr('data-graphid'),
      legend_box: $legend_box
    });
    $grapher = $plot_box.data('grapher');

    // Setup actions on buttons toolbar
    $this.find('[data-graphrole="offon-series"]').data('selectall', 'true').click(function (e) {
      e.preventDefault();
      var selectall = !$(this).data('selectall');
      if (selectall)
          $grapher.activateSeries();
      else
          $grapher.deactivateSeries();
      $(this).data('selectall', selectall);
    });

    $this.find('[data-graphrole="invert-series"]').click(function(e){
      e.preventDefault();
      $grapher.invertActivatedSeries();
    });
    // Export the graph
    $this.find('[data-graphrole="export-graph"]').click(function(e){
        e.preventDefault();
        $grapher.export();
    });



    $grapher.observe('grapher:zoomed', function (from, to) {
        var $this = $(this),
          grapher  = $this.grapher();

        // FIXME: do not use flotr props to get min/max date
        $(this).parent().siblings().find('> span').get(0)
          .innerHTML = ''+ grapher.formatDate(new Date(grapher.flotr.axes.x.datamin), grapher.fetched.properties.xaxis.timeFormat, grapher.fetched.properties.xaxis.timeMode)
            +'&nbsp;&nbsp;-&nbsp;&nbsp;'+ grapher.formatDate(new Date(grapher.flotr.axes.x.datamax),  grapher.fetched.properties.xaxis.timeFormat, grapher.fetched.properties.xaxis.timeMode);
    });
  });

  $('.scales input[type=button]').click(function () {
    var fromDate = new Date(),
      toDate = new Date(),
      frompick = $('#fromdatepick').data('datetimepicker'),
      topick = $('#todatepick').data('datetimepicker');

    switch($(this).attr('id')) {
      case 'sel_year':
          fromDate.setYear(fromDate.getYear() + 1900 - 1);
        break;
        case 'sel_month':
          fromDate.setMonth(fromDate.getMonth() - 1);
        break;
        case 'sel_week':
          fromDate.setDate(fromDate.getDate() - 7);
        break;
        case 'sel_day':
          fromDate.setDate(fromDate.getDate() - 1);
        break;
        case 'sel_custom':
          if (frompick.getDate() === null ) {
            alert('you must set the starting date.');
            return false;
          }
          if (topick.getDate() === null) {
            /* set the toDate to the current day */
            topick.setLocalDate(toDate.getDate());
          }
          else { toDate = topick.getLocalDate(); }

          fromDate = frompick.getLocalDate();
        break;
    }
    frompick.setLocalDate(fromDate);
    topick.setLocalDate(toDate);
    $('[data-graphrole="plot"]').each(function (i, e) {
        $(this).grapher().zoom(
            frompick.getLocalDate().getTime(),
            topick.getLocalDate().getTime()
        );
    });
  });

  $('.go-forward').click(function (e) {
    var frompick = $('#fromdatepick').data('datetimepicker'),
      topick   = $('#todatepick').data('datetimepicker'),
      fromDate = frompick.getLocalDate().getTime(),
      toDate   = topick.getLocalDate().getTime(),
      delta    = toDate - fromDate;

    e.preventDefault();

    fromDate += delta;
    toDate   += delta;

    frompick.setLocalDate(new Date(fromDate));
    topick.setLocalDate(new Date(toDate));

    $('[id-graph]').each(function (i, e) {
        $(e).grapher().zoom(
            frompick.getLocalDate().getTime(),
            topick.getLocalDate().getTime()
        );
    });
  });

  $('.go-backward').click(function (e) {
    var frompick = $('#fromdatepick').data('datetimepicker'),
      topick   = $('#todatepick').data('datetimepicker'),
      fromDate = frompick.getLocalDate().getTime(),
      toDate   = topick.getLocalDate().getTime(),
      delta    = toDate - fromDate;

    e.preventDefault();

    fromDate -= delta;
    toDate   -= delta;

    frompick.setLocalDate(new Date(fromDate));
    topick.setLocalDate(new Date(toDate));

    $('[id-graph]').each(function (i, e) {
        $(e).grapher().zoom(
            frompick.getLocalDate().getTime(),
            topick.getLocalDate().getTime()
        );
    });
  });

  /* by default, show the week graph by triggering the week button */
  $('#sel_week').click();

  /* show tooltips */
  $('a[title]').tooltip();

  /* confirm on clone */
  $('.btn_clone_graph').click(function () {
      return confirm('Do you really want to clone this graph ?');
  });
});
