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
  // Responsive: collapse to an icon rail under 769px (matches the old $(window)<769 check).
  function syncBodySmall() {
    $('body').toggleClass('body-small', $(window).width() < 769);
  }
  syncBodySmall();
  $(window).on('resize', syncBodySmall);

  // Sidebar accordion (nested .nav-second-level / .nav-third-level).
  $('#side-menu').metisMenu();

  // Minimalize (hamburger) — collapse the sidebar to an icon rail.
  $('.navbar-minimalize').on('click', function (e) {
    e.preventDefault();
    $('body').toggleClass('mini-navbar');
    smoothlyMenu();
  });

  // .ibox tools.
  $('.collapse-link').on('click', function (e) {
    e.preventDefault();
    var ibox = $(this).closest('div.ibox');
    var icon = $(this).find('i');
    ibox.find('div.ibox-content').slideToggle(200);
    icon.toggleClass('fa-chevron-up').toggleClass('fa-chevron-down');
    ibox.toggleClass('border-bottom');
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
