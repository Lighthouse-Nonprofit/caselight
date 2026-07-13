// POAM-017g Q1: krajee fileinput 5 renders more default chrome than 4.4.1 did with the
// same per-site options — a drag&drop zone, a Remove button, and a floating close icon
// appear on every widget (the BS3-era baseline was a compact "field + Browse" control).
// Restore the compact baseline app-wide; individual init sites can still opt back in.
(function ($) {
  'use strict';
  if (!$.fn.fileinput) return;
  $.extend($.fn.fileinput.defaults, {
    showUpload: false,
    showRemove: false,
    showClose: false,
    showCancel: false,
    dropZoneEnabled: false,
  });

  // Disarm the plugin's bundled auto-init: on document-ready it calls
  // $('input.file[type=file]').fileinput() with NO arguments (simple_form file inputs
  // carry class="file"), racing the app's explicit per-page inits. On the assessment
  // wizard, jquery.steps rebuilds the step DOM between the two, stripping the jQuery
  // data that makes re-init a no-op — the explicit init then nested a SECOND widget
  // inside the auto-widget's Browse button. Every CaseLight site initializes explicitly
  // with options; a zero-argument call can only be that auto-init sweep, so drop it.
  var plugin = $.fn.fileinput;
  $.fn.fileinput = function () {
    if (arguments.length === 0) return this;
    return plugin.apply(this, arguments);
  };
  $.extend($.fn.fileinput, plugin); // keep .defaults / .Constructor
})(jQuery);
