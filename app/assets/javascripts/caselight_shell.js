// caselight_shell.js (POAM-017g THE FLIP) — the LIVE shell behaviours ported from the
// deleted INSPINIA wrapbootstrap/inspinia.js. Bootstrap 5's bundle now owns
// modal/dropdown/collapse/tab; this file keeps only the app-specific chrome:
//   * the collapsible sidebar (metisMenu accordion + the mini-navbar hamburger toggle),
//   * the .ibox tools (collapse / close / fullscreen),
//   * the responsive body-small class,
//   * declarative tooltip/popover init (BS5-native, data-bs-toggle="tooltip|popover").
// DROPPED from inspinia.js (dead demo chrome / superseded plumbing): slimscroll (the shell
// now uses native overflow-y), the right sidebar + small chat + todo check-links, the
// localStorage layout prefs, WinMove draggable panels, animationHover, and fix_height (the
// flexbox shell in caselight_theme/_shell.scss sizes itself).

$(function () {
  // UX round 3 (D3/R9) — sidebar collapse persistence. The desktop state survives page loads
  // via a cookie the LAYOUT reads server-side (body renders with mini-navbar — no FOUC; the
  // once-dropped localStorage approach would flash expanded before JS ran).
  function persistSidebar(state) {
    document.cookie = 'cl_sidebar=' + state + '; path=/; max-age=31536000; SameSite=Lax';
  }

  // Responsive: collapse to an icon rail under 769px (matches the old $(window)<769 check).
  // D3 semantics trap: mini-navbar means "collapsed rail" on desktop but "overlay OPEN" on
  // small screens — strip it when ENTERING the small state so a desktop cookie can never
  // open the mobile overlay (the matching pure-CSS mobile open rules left _shell.scss too).
  var wasSmall = null;
  function syncBodySmall() {
    var small = $(window).width() < 769;
    if (small && wasSmall !== true) {
      $('body').removeClass('mini-navbar');
    }
    wasSmall = small;
    $('body').toggleClass('body-small', small);
  }
  syncBodySmall();
  $(window).on('resize', syncBodySmall);

  // Sidebar accordion (nested .nav-second-level / .nav-third-level).
  $('#side-menu').metisMenu();

  // Minimalize (hamburger) — collapse the sidebar to an icon rail. Desktop toggles persist.
  $('.navbar-minimalize').on('click', function (e) {
    e.preventDefault();
    $('body').toggleClass('mini-navbar');
    if (!$('body').hasClass('body-small')) {
      persistSidebar($('body').hasClass('mini-navbar') ? 'mini' : 'full');
    }
    smoothlyMenu();
  });

  // UX round 3 (D3/R9) — selecting a menu item collapses the sidebar again. Leaf links only
  // (metisMenu accordion parents use href="#"). Mobile: close the overlay immediately while
  // the page loads. Desktop: no mid-navigation jank — the cookie makes the NEXT page render
  // as the icon rail; the hamburger re-expands (and persists) whenever the user wants it back.
  $('#side-menu').on('click', 'a[href]:not([href="#"])', function () {
    if ($(this).closest('.nav-header').length) {
      return;
    }
    if ($('body').hasClass('body-small')) {
      $('body').removeClass('mini-navbar');
    } else {
      persistSidebar('mini');
    }
  });

  // .ibox tools. UX round 3 (D2/R8): `.collapsed` on the .ibox is the single source of truth —
  // the CSS glyph swap in _ibox.scss keys off it (markup always ships fa-chevron-up), and the
  // server pre-collapses empty sections by rendering the class (shared/_ibox_collapse_link +
  // ibox_classes helper). slideToggle's inline display wins over the .collapsed CSS rule, so a
  // server-collapsed box expands correctly on the first click.
  $('.collapse-link').on('click', function (e) {
    e.preventDefault();
    var ibox = $(this).closest('div.ibox');
    ibox.find('div.ibox-content').stop(true, true).slideToggle(200);
    ibox.toggleClass('collapsed').toggleClass('border-bottom');
    $(this).attr('aria-expanded', String(!ibox.hasClass('collapsed')));
  });
  $('.close-link').on('click', function (e) {
    e.preventDefault();
    $(this).closest('div.ibox').remove();
  });
  $('.fullscreen-link').on('click', function (e) {
    e.preventDefault();
    var ibox = $(this).closest('div.ibox');
    var icon = $(this).find('i');
    $('body').toggleClass('fullscreen-ibox-mode');
    icon.toggleClass('fa-expand').toggleClass('fa-compress');
    ibox.toggleClass('fullscreen');
  });

  // Declarative tooltips + popovers (BS5-native; the flip codemod renamed
  // data-toggle -> data-bs-toggle). getOrCreateInstance is idempotent.
  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (el) {
    bootstrap.Tooltip.getOrCreateInstance(el);
  });
  document.querySelectorAll('[data-bs-toggle="popover"]').forEach(function (el) {
    bootstrap.Popover.getOrCreateInstance(el);
  });

  // iCheck event compat (POAM-017g flip): iCheck is removed and checkboxes/radios are native
  // Bootstrap-5 .form-check controls now. iCheck's command calls were rewritten to native
  // prop()+change; re-fire iCheck's ifChecked/ifUnchecked/ifChanged custom events on native
  // change so the remaining .on('ifChecked'/'ifUnchecked', …) handlers keep working unchanged.
  $(document).on('change', 'input[type=checkbox], input[type=radio]', function () {
    $(this).trigger(this.checked ? 'ifChecked' : 'ifUnchecked').trigger('ifChanged');
  });
});

// Hide/re-show #side-menu briefly so the width transition is smooth (ported from INSPINIA
// SmoothlyMenu; trimmed to the two states this app uses).
function smoothlyMenu() {
  var body = $('body');
  if (!body.hasClass('mini-navbar') || body.hasClass('body-small')) {
    $('#side-menu').hide();
    setTimeout(function () { $('#side-menu').fadeIn(400); }, 200);
  } else {
    $('#side-menu').removeAttr('style');
  }
}
