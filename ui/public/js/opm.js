/**
 * Global javascript file
 *
 * This program is open source, licensed under the PostgreSQL License.
 * For license terms, see the LICENSE file.
 *
 * Copyright (C) 2012-2014: Open PostgreSQL Monitoring Development Group
**/
function displayResult(item, val, text) {
    window.location = '/server/' + val;
}

function confirmDel(kind, name){
  var ret = confirm('Do you really want to delete the ' + kind + ' "' + name + '" ?');
  return ret;
}

$(document).ready(function (){
    $('#search').typeahead({
      ajax: { url: searchUrl, triggerLength: 1},
      itemSelected: displayResult
    });
});
