CIF.Initializer = {
  exec(pageName) {
    if (pageName && CIF[pageName]) {
      return CIF[pageName]['init']();
    }
  },

  currentPage() {
    if (!$('body').attr('id')) {
      return '';
    }

    const bodyId = $('body').attr('id').split('-');
    const action = CIF.Util.capitalize(bodyId[1]);
    const controller = CIF.Util.capitalize(bodyId[0]);
    return controller + action;
  },

  init() {
    CIF.Initializer.exec('Common');
    if (this.currentPage()) {
      return CIF.Initializer.exec(this.currentPage());
    }
  },
};

// jQuery-3 prep (POAM-017b): the 'ready' EVENT was removed in jQuery 3 (and jquery-migrate
// does not restore it) — binding it via .on() would leave this app-wide dispatcher, and
// therefore ALL page JS, silently dead after the upgrade. $(handler) is the supported form
// on every jQuery version. 'page:load' was a vestigial Turbolinks event (no turbolinks here).
$(() => CIF.Initializer.init());
