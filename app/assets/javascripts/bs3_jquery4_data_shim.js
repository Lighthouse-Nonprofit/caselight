// TEMPORARY Bootstrap-3-on-jQuery-4 shim (POAM-017g P6) — DIES AT THE BS5 FLIP together
// with bootstrap-sprockets (flip deletion list).
//
// jQuery 4's bulk .data() (no-argument form) returns a NULL-PROTOTYPE object. Bootstrap
// 3.4.1 feeds that object to Object.prototype APIs in at least two places:
//   - collapse's data-api Plugin: `/show|hide/.test(option)` — no toString to coerce with
//     -> "Cannot convert object to primitive value" -> EVERY first-click declarative
//     collapse dead (index search-filter panels included);
//   - tooltip/popover getOptions (3.4's sanitizer): `dataAttributes.hasOwnProperty(...)`
//     -> "hasOwnProperty is not a function" -> every tooltip/popover init dead (e.g. the
//     family-show member-count popover; inspinia's ready-time init throws).
// Both broke silently at the jQuery 4 bump (12D) and were caught by the P6 interaction
// gate (qa/playwright/bs5_interactions.js).
//
// ONE fix at the root: wrap the bulk read so it returns a NORMAL-prototype copy. Keyed and
// setter calls pass through untouched. This normalization exists solely for Bootstrap 3's
// internals — BS5 is jQuery-free, so the whole file is deleted at the flip.
// (Not in jquery4_compat.js by design: that file is guard-pinned to censused API
// RESTORATIONS and bans jQuery.fn.* additions.)
(function ($) {
  'use strict';
  if (!$ || !$.fn || !$.fn.data) return;

  var origData = $.fn.data;
  $.fn.data = function () {
    var out = origData.apply(this, arguments);
    if (arguments.length === 0 && out && typeof out === 'object' &&
        Object.getPrototypeOf(out) === null) {
      out = $.extend({}, out);
    }
    return out;
  };
})(window.jQuery);
