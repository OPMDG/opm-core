$(document).ready(function (){
  $('.checkall').click(function ( e ) {
    e.preventDefault();
    $(this).parents('table').find('tbody input').prop('checked', true);
  });

  $('.uncheckall').click(function ( e ) {
    e.preventDefault();
    $(this).parents('table').find('tbody input').prop('checked', false);
  });

  $('.invertcheck').click(function ( e ) {
    e.preventDefault();
    $(this).parents('table').find('tbody input').each(function(){
      $(this).prop('checked', !$(this).is(':checked'));
    });
  });
});

function confirmDelService(server, service){
  if ( service == '' )
    str = 'selected services';
  else
    str = 'service "' + service + '"';

  return confirm('Do you really want to delete the ' + str + ' (server "' + server + '") ?');
}

function confirmDelLabel(server, service, label){
  if ( label == '' )
    str = 'selected labels';
  else
    str = 'label "' + label + '"';

  return confirm('Do you really want to delete the ' + str + ' (service "' + service + '" on server "' + server + '") ?');
}
