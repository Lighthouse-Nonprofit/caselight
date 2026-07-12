// jquery4_compat.js — the four jQuery-4-removed utilities the aging vendored plugin set
// still calls, restored explicitly. This file REPLACED the jquery-migrate 4.0.2 bridge
// (post-CSP-soak cleanup): migrate restored ~everything and console.warned each use; this
// restores ONLY what a caller census found live, with jQuery's own semantics, silently.
//
// Census (2026-07-12, recursive grep of vendor/ + app/ assets — see the guard spec, which
// pins this list and bans growth):
//   jQuery.isFunction — iCheck (login checkboxes), footable, jquery.infinitescroll
//   jQuery.proxy      — bootstrap_file_input (x10), metisMenu, jquery.infinitescroll
//   jQuery.trim       — bootstrap_file_input (x4), footable
//   jQuery.camelCase  — form-builder.min (formBuilder 3.23)
//
// Do NOT add entries here without a caller census; app code must use the modern forms
// (the removed-API guard spec bans these in app javascripts). Each restoration defers to
// core if a future jQuery build ships the method again.
(function(jQuery) {
  'use strict';
  if (!jQuery) { return; }

  // jQuery's guarded form: excludes DOM objects that typeof as "function" (old IE quirks
  // aside, the nodeType/item guards are upstream's — keep fidelity for the vendored callers).
  jQuery.isFunction = jQuery.isFunction || function(obj) {
    return typeof obj === 'function' &&
      typeof obj.nodeType !== 'number' &&
      typeof obj.item !== 'function';
  };

  // Both upstream signatures: (fn, context, ...args) and (context, methodName, ...args).
  // guid propagation is LOAD-BEARING: plugins unbind proxied handlers via the original
  // function reference (jQuery matches them by guid) — Function#bind alone breaks .off().
  jQuery.proxy = jQuery.proxy || function(fn, context) {
    var tmp, args, proxy;
    if (typeof context === 'string') {
      tmp = fn[context];
      context = fn;
      fn = tmp;
    }
    if (typeof fn !== 'function') { return undefined; }
    args = Array.prototype.slice.call(arguments, 2);
    proxy = function() {
      return fn.apply(context || this, args.concat(Array.prototype.slice.call(arguments)));
    };
    proxy.guid = fn.guid = fn.guid || jQuery.guid++;
    return proxy;
  };

  // Upstream's exact charset (whitespace + BOM + nbsp), escaped — not String#trim —
  // for byte-for-byte fidelity with what the vendored callers expect.
  var rtrim = new RegExp('^[\\s\\uFEFF\\xA0]+|[\\s\\uFEFF\\xA0]+$', 'g');
  jQuery.trim = jQuery.trim || function(text) {
    return text == null ? '' : (text + '').replace(rtrim, '');
  };

  // Upstream's css-name camelizer incl. the -ms- vendor-prefix special case.
  var rmsPrefix = /^-ms-/;
  var rdashAlpha = /-([a-z])/g;
  jQuery.camelCase = jQuery.camelCase || function(string) {
    return string.replace(rmsPrefix, 'ms-').replace(rdashAlpha, function(all, letter) {
      return letter.toUpperCase();
    });
  };
})(window.jQuery);
