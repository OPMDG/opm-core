/**
 * Global javascript file
 *
 * This program is open source, licensed under the PostgreSQL License.
 * For license terms, see the LICENSE file.
 *
 * Copyright (C) 2012-2013: Open PostgreSQL Monitoring Development Group
**/
function displayResult(item, val, text) {
      console.log(item);
          window.location = '/server/' + val;
}

function confirmDel(kind, name){
  var ret = confirm('Do you really want to delete the ' + kind + ' "' + name + '" ?');
  return ret;
}

$(document).ready(function (){
    $('#search').typeahead({
      ajax: { url: '/search/server', triggerLength: 1},
      itemSelected: displayResult
    });
});
