// shared/date_picker.js (POAM-017g THE FLIP) — vanillajs-datepicker adapter.
//
// Replaces the bootstrap-datepicker global init (the old app/assets/javascripts/datepicker.js)
// AND the bootstrap-datepicker jQuery plugin the rule builder embedded. vanillajs-datepicker is
// jQuery-free and binds an <input> (NOT a wrapping `.input-group`); this adapter resolves the
// inner input of an `.input-group.date` component and wires the calendar addon to open it.
//
// FORMAT IS ISO yyyy-mm-dd AT EVERY SITE (P6 audit / BS5-FLIP-AUDITS.md). The vendored en-GB
// locale supplies only month/day NAMES — its own `format: dd/mm/yyyy` is overridden per-instance
// here. The interaction gate (qa/playwright/bs5_interactions.js #7) pins the yyyy-mm-dd shape.
// vanillajs stores each instance on `input.datepicker`, which this adapter uses for idempotency
// (the two init selectors overlap on the today-default sites) and for destroy().

CIF.DatePicker = (function () {
  var DEFAULTS = {
    format: 'yyyy-mm-dd',   // overrides the en-GB locale's dd/mm/yyyy
    language: 'en-GB',
    autohide: true,         // bootstrap-datepicker's `autoclose`
    todayHighlight: true,
    // `disableTouchKeyboard` has no vanillajs equivalent — dropped (P6 audit note).
  };

  // Resolve the <input> vanillajs should bind, plus the optional addon to wire for opening.
  function resolve(node) {
    var $node = $(node);
    if ($node.is('input')) {
      var $group = $node.closest('.input-group.date');
      return {
        input: node,
        addon: $group.length ? $group.find('.input-group-text').get(0) : null,
      };
    }
    // An `.input-group.date` container: bind its inner (non-hidden) input, wire its addon.
    var input = $node.find('input').not('[type=hidden]').get(0);
    if (!input) return null;
    return { input: input, addon: $node.find('.input-group-text').get(0) };
  }

  function attach(node, opts) {
    var r = resolve(node);
    if (!r || !r.input) return null;
    if (r.input.disabled) { destroy(r.input); return null; }
    if (r.input.datepicker) return r.input.datepicker; // idempotent — don't double-bind
    var dp = new Datepicker(r.input, $.extend({}, DEFAULTS, opts || {}));
    if (r.addon && !r.addon.dataset.clDpWired) {
      r.addon.dataset.clDpWired = '1';
      r.addon.style.cursor = 'pointer';
      r.addon.addEventListener('click', function () { r.input.focus(); });
    }
    return dp;
  }

  function destroy(input) {
    if (input && input.datepicker && typeof input.datepicker.destroy === 'function') {
      input.datepicker.destroy();
    }
  }

  function init() {
    // Global sites (bare inputs + .date_filter + .input-group.date components).
    $('.date_filter, .input-group.date, #csi_start_date, #csi_end_date, #case_start_date, #case_end_date')
      .each(function () { attach(this); });

    // Sites that default to TODAY.
    $('form.new_client .client_date_of_birth #client_initial_referral_date, form.new_case #case_start_date, .modal#exitFromCase #case_exit_date, form#new_progress_note #progress_note_date')
      .each(function () {
        var dp = attach(this);
        if (dp) dp.setDate(new Date());
      });

    // Disabled date inputs get no picker (was `.datepicker('remove')`).
    $('input.date[disabled="disabled"]').each(function () { destroy(this); });
  }

  return { init: init, attach: attach, destroy: destroy, DEFAULTS: DEFAULTS };
})();

$(function () { CIF.DatePicker.init(); });
