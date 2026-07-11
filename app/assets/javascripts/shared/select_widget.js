// POAM-017c — CIF.Select: one shared adapter over Tom Select 2.x, replacing the
// hand-vendored select2 3.5.2 (2014, unmaintained) on every former .select2() site.
//
// Design rules:
// - init() is IDEMPOTENT (skips non-selects and already-initialized elements) — the
//   advanced-search/program-stream query-builder choreography re-runs init after the
//   builder swaps rule selects, exactly like the old repeated .select2() calls.
// - The underlying <select> stays the source of truth: Tom Select keeps it synced and
//   dispatches a native 'change', so existing $(sel).on('change') listeners (datagrid
//   filters, queryBuilder internals, location toggles) keep working unmodified.
// - select2-option mapping: allowClear -> clear_button plugin; multiple selects get
//   remove_button (the old per-chip x); minimumInputLength is dropped (Tom Select
//   always searches); width:'NNNpx' -> wrapper style, width:'resolve' -> theme default.
// - maxOptions:null and allowEmptyOption:true restore select2 behavior (show every
//   option; keep Rails include_blank/prompt options selectable).
CIF.Select = (function () {
  const DEFAULTS = {
    create: false,
    maxOptions: null, // select2 listed every option; Tom Select defaults to 50
    allowEmptyOption: true, // Rails include_blank/prompt blanks stay selectable
  };

  const element = function (target) {
    return target instanceof jQuery ? target[0] : target;
  };

  const instance = function (target) {
    const el = element($(target).get(0) ? $(target).get(0) : target);
    return el ? el.tomselect : undefined;
  };

  const init = function (selector, opts) {
    const extra = Object.assign({}, opts || {});
    const width = extra.width;
    const allowClear = extra.allowClear;
    delete extra.width;
    delete extra.allowClear;
    delete extra.minimumInputLength; // select2-ism; searching is always on
    delete extra.theme; // select2-bootstrap theme flag; styling lives in tom_select_bs3.scss

    return $(selector).each(function () {
      if (this.tagName !== 'SELECT' || this.tomselect) {
        return;
      }
      const plugins = [];
      if (this.multiple) {
        plugins.push('remove_button');
      } else if (allowClear) {
        plugins.push('clear_button');
      }
      const ts = new TomSelect(this, Object.assign({ plugins }, DEFAULTS, extra));
      if (width && width !== 'resolve') {
        ts.wrapper.style.width = width;
      }
    });
  };

  // select2('val', x) equivalent. Silent by default — select2 v3's 'val' did NOT fire
  // change, and the former call sites do their own follow-up work.
  const setValue = function (selector, value, silent) {
    if (silent === undefined) {
      silent = true;
    }
    return $(selector).each(function () {
      if (this.tomselect) {
        const v = value === '' || value === null || value === undefined ? (this.multiple ? [] : '') : value;
        this.tomselect.setValue(v, silent);
      } else {
        $(this).val(value);
      }
    });
  };

  const destroy = function (selector) {
    return $(selector).each(function () {
      if (this.tomselect) {
        this.tomselect.destroy();
      }
    });
  };

  // Bind a Tom Select instance event on every matched, initialized select.
  // handler(value, selectEl, tsArg2): covers every former select2-selecting /
  // select2-removed / select2-close site — the option's TEXT (select2's
  // element.choice.text) is recovered via optionText(el, value).
  //   item_add       <- select2-selecting  (fires after add; the app's handlers react,
  //                                         none veto, verified per-site in the R7 sweep)
  //   item_remove    <- select2-removed
  //   dropdown_close <- select2-close
  const on = function (selector, event, handler) {
    return $(selector).each(function () {
      const el = this;
      if (el.tomselect) {
        el.tomselect.on(event, function (a, b) {
          return handler(a, el, b);
        });
      }
    });
  };

  // Re-import options after code rebuilds the native select's <option>s via .html()/.append().
  // select2 v3 read the DOM live on every open; Tom Select caches options, so a native
  // rebuild must be followed by clear + clearOptions + sync (sync re-reads the original element).
  const refresh = function (selector) {
    return $(selector).each(function () {
      if (this.tomselect) {
        this.tomselect.clear(true);
        this.tomselect.clearOptions();
        this.tomselect.sync();
      }
    });
  };

  // Non-destructive option-state resync: re-imports the native <option>s (including
  // disabled-attribute toggles) while PRESERVING the current selection. For the
  // mutual-exclusion selects that flip option disabled flags on each other natively —
  // select2 v3 read those live from the DOM on every open.
  const resyncOptions = function (selector) {
    return $(selector).each(function () {
      const ts = this.tomselect;
      if (ts) {
        const items = ts.items.slice(); // primitive source of truth (not getValue())
        ts.clearOptions();
        ts.sync();
        ts.setValue(items, true);
      }
    });
  };

  // replaces $(sel).attr('disabled', ...) toggles — Tom Select ignores post-init attribute
  // changes; ts.disable()/enable() grey the control AND set the native select's disabled
  // flag (preserving the don't-submit-when-disabled form semantics the old code relied on)
  const disable = function (selector) {
    return $(selector).each(function () {
      if (this.tomselect) {
        this.tomselect.disable();
      } else {
        this.disabled = true;
      }
    });
  };

  const enable = function (selector) {
    return $(selector).each(function () {
      if (this.tomselect) {
        this.tomselect.enable();
      } else {
        this.disabled = false;
      }
    });
  };

  const optionText = function (target, value) {
    const el = element($(target).get(0) ? $(target).get(0) : target);
    const opt = el && el.querySelector('option[value="' + String(value).replace(/"/g, '\\"') + '"]');
    return opt ? opt.textContent : '';
  };

  const selectedText = function (selector) {
    const el = $(selector).get(0);
    if (!el) {
      return '';
    }
    const opt = el.options[el.selectedIndex];
    return opt ? opt.textContent : '';
  };

  return {
    init,
    setValue,
    destroy,
    on,
    instance,
    refresh,
    resyncOptions,
    disable,
    enable,
    optionText,
    selectedText,
  };
})();
