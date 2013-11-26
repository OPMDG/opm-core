/**
 * Javascript for page host.html.ep
 **/
$(document).ready(function () {
    $('.show-all').click(function (e) {
        $('.accordion-body').collapse('show');
    });
    $('.hide-all').click(function (e) {
        $('.accordion-body').collapse('hide');
    });
});