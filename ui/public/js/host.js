/**
 * Javascript for page host.html.ep
 *
 * This program is open source, licensed under the PostgreSQL License.
 * For license terms, see the LICENSE file.
 *
 * Copyright (C) 2012-2013: Open PostgreSQL Monitoring Development Group
**/
$(document).ready(function () {
    $('.show-all').click(function (e) {
        $('.accordion-body').collapse('show');
    });
    $('.hide-all').click(function (e) {
        $('.accordion-body').collapse('hide');
    });
});
