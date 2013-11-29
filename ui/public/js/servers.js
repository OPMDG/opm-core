/**
 * Javascript for page list.html.ep
 *
 * This program is open source, licensed under the PostgreSQL License.
 * For license terms, see the LICENSE file.
 *
 * Copyright (C) 2012-2013: Open PostgreSQL Monitoring Development Group
**/
$(document).ready(function (){
    $('.collapse').on('hide', function () {
        $(this).parent().find('.accordion-heading > a > i')
            .removeClass('icon-minus').addClass('icon-plus');
    });
    $('.collapse').on('show', function () {
        $(this).parent().find('.accordion-heading > a > i')
            .removeClass('icon-plus').addClass('icon-minus');
    });

    $('.show-all').click(function (e) {
        $('.collapse').collapse('show');
    });
    $('.hide-all').click(function (e) {
        $('.collapse').collapse('hide');
    });

    if ( $('.accordion-group').length == 1 )
        $('.collapse').collapse('show');
});
