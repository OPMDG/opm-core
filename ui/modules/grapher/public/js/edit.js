/**
 * Javascript for page edit.html.ep
 *
 * This program is open source, licensed under the PostgreSQL License.
 * For license terms, see the LICENSE file.
 *
 * Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group
**/

function toggleGraphType(){
  $('.graph_type').hide();
  $('#type_'+$('#graph_type_select').find('option:selected').val()).show();
}

$(document).ready(function () {
  // Handle graph type selector
  $('#graph_type_select').change(function (e) {
    if ( $('#graph_type_select option:selected').val() != '') {
      toggleGraphType();
    }
  });

  $('#btn_drop_graph').click(function () {
      return confirm('Do you really want to drop this graph ?');
  });

  // Need to call it the first time
  toggleGraphType();
});
