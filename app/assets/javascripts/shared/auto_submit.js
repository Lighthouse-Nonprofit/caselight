// CSP-reduction (POAM-017f / 12C-1): replaces the LAST two inline
// `onchange="this.form.submit()"` handlers on browser-served pages (the clients/families
// index card-grid sort selects). Attribute-driven like rails-ujs: any select carrying
// data-auto-submit submits its enclosing form on change. Delegated on document so it
// survives re-renders and catches the change event Tom Select dispatches on the native
// select it wraps; native form.submit() preserves the inline handler's exact semantics.
// Defensive no-op everywhere else.
$(document).on('change', 'select[data-auto-submit]', function () {
  if (this.form) {
    this.form.submit();
  }
});
