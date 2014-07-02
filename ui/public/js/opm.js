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

function displayError(text, error_type) {
    var errtype = error_type != undefined ? error_type : "danger",
        tmp = '<div class="alert fade in alert-' + errtype + '">'
        + '<button type="button" class="close" data-dismiss="alert">&times;</button>'
        + '<ul class="unstyled">'
        + '<li>' + text + '</li>'
        + '</ul></div>';
    $('#main').prepend(tmp);
    return tmp;
}

$(document).ready(function (){
    $('[data-searchurl]').each(function () {
        var $this = $(this);
        $this.typeahead({
            ajax: { url: $this.attr('data-searchurl'), triggerLength: 1},
            itemSelected: displayResult
        });
    });
    $('[data-role="tagsinput"]').each(function () {
        var $this = $(this),
            url = $this.attr('data-tagupdateurl'),
            updateTags;
            if(!url){
                return;
            }
            updateTags = function(tag, callback){
                var tagElem = $this.data('tagsinput').$container.find('.tag:contains("' + tag + '")');
                if($this.data('pending_change')){
                    return;
                }
                $this.data('pending_change', true);
                tagElem.css("opacity", 0.2);
                var deferred = $.ajax({
                    url: url,
                    type: 'POST',
                    traditional: true,
                    data: {'tags': $this.tagsinput('items') }
                });
                callback(tagElem, deferred).always(function(){
                    $this.data('pending_change', false);
                }).done(function () {
                    $this.trigger('tagSaved', {items: $this.tagsinput('items')});
                }).fail(function () {
                    displayError("Échec de la sauvegarde");
                });
            };
            $this.data('pending_change', false);
            $this.on('itemAdded', function (event){
                var tag = event.item;
                updateTags(tag, function(tagElem, deferred){
                    return deferred.fail(function(){
                        $this.tagsinput('remove', tag);
                    }).done(function(){
                        tagElem.animate({'opacity': 1});
                    });
                });
            });
            $this.on('itemRemoved', function (event){
                var tag = event.item;
                updateTags(tag, function(tagElem, deferred){
                    $this.tagsinput('add', tag);
                    return deferred.fail(function(){
                        tagElem.animate({'opacity': 1});
                    }).done(function(){
                        $this.tagsinput('remove', tag);
                    });
                });
            });
    });
    // Each tag-cloud listens for tagSaved events on the tagInputs.
    $('[data-role="tag-cloud"]').each(function(){
        var $this = $(this);
        $('[data-role="tagsinput"]').on('tagSaved', function(event){
            var keys = {},
                selected = {},
                target_url = $this.attr('data-targeturl'),
                base_class = $this.attr('data-baseclass'),
                selected_class = $this.attr('data-selectedclass');
            if(!target_url.contains("?")){
                target_url += "?";
            }
            // Collect a set of all tags present on the page
            // XXX: qualify this better if we ever use tagsinput for
            // something else
            $('.bootstrap-tagsinput .tag').each(function(key){
                keys[$(this).text()] = "on";
            });
            // Collect already selected tagsinput, if any.
            $this.find('.' + selected_class).each(function(key){
                selected[key] = "on";
            });
            $this.empty();
            // Build the new list.
            $this.append($.map(Object.keys(keys).sort(), function(key){
                var curr_class = selected[key] ? selected_class : base_class;
                return $('<a>')
                    .attr('href', target_url + "tags=" + key )
                    .text(' ' + key + ' ')
                    .prepend(
                        $('<i>')
                        .addClass("fa")
                        .addClass(curr_class));
            }));
        });
    });
});
