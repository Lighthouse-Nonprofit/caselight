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

  // C1 — mini-rail affordance state. Desktop-mini is the ONLY state where the rail is
  // icon-only, so it is the only state where the nav tooltips are live (and, in C2, where
  // the #manage flyout arms). One idempotent sync, called from boot + hamburger + resize.
  var navTooltips = [];
  function isDesktopMini() {
    return $('body').hasClass('mini-navbar') && !$('body').hasClass('body-small');
  }
  function syncMiniAffordances() {
    var mini = isDesktopMini();
    navTooltips.forEach(function (t) {
      if (mini) { t.enable(); } else { t.disable(); t.hide(); }
    });
    // C2 — arm/disarm the #manage flyout ARIA contract with the same state.
    var manage = document.getElementById('manage');
    if (manage) {
      if (mini) {
        manage.setAttribute('aria-haspopup', 'true');
        if (!manage.hasAttribute('aria-expanded')) { manage.setAttribute('aria-expanded', 'false'); }
        manage.setAttribute('aria-controls', 'cl-flyout-manage');
      } else {
        closeFlyout(false);
        manage.removeAttribute('aria-haspopup');
        manage.removeAttribute('aria-expanded');
        manage.removeAttribute('aria-controls');
      }
    }
  }

  // ------------------------------------------------------------------------------------------------
  // C2 — the #manage flyout for the desktop-mini rail. The in-rail accordion is force-hidden in
  // mini (overflow would clip it), which used to make the cogs icon a dead click. The flyout is a
  // position:fixed panel APPENDED TO document.body (escapes the rail's overflow-x:hidden; body has
  // no transform on desktop) carrying `dropdown-menu` classes so it inherits the BS5 surface,
  // $dropdown-box-shadow, the permanent _compat li>a item shim, the _focus-ring keyboard ring and
  // the _motion cl-pop entrance FOR FREE. Content is a LAZY RUNTIME CLONE of the server-rendered
  // ul.nav-second-level — the server already rendered exactly what this user is authorized to see,
  // so there is no double render and no authz drift; the nested third level ("Progress Note")
  // flattens under a subheader. metisMenu coexistence: a document-level CAPTURE-phase gate owns
  // trusted #manage clicks in desktop-mini only — common.js's SYNTHETIC open-on-load click
  // (e.isTrusted === false) falls through to metisMenu, and expanded/mobile behavior is untouched.
  // ------------------------------------------------------------------------------------------------
  var flyout = null;

  function buildFlyout() {
    if (flyout) { return flyout; }
    var manage = document.getElementById('manage');
    var source = manage && manage.parentElement.querySelector('ul.nav-second-level');
    if (!source) { return null; }

    flyout = document.createElement('div');
    flyout.className = 'cl-sidebar-flyout dropdown-menu';
    flyout.id = 'cl-flyout-manage';

    var title = document.createElement('div');
    title.className = 'cl-sidebar-flyout__title';
    title.textContent = ($(manage).find('.nav-label').text() || 'Manage').trim();
    flyout.appendChild(title);

    var list = source.cloneNode(true);
    list.className = 'cl-sidebar-flyout__list';
    // metisMenu residue: collapse-state classes + the inline height common.js's synthetic
    // open may have left, plus the decorative chevrons.
    $(list).find('.collapse, .collapsing, .in').removeClass('collapse collapsing in');
    $(list).find('[style]').removeAttr('style');
    $(list).find('.fa.arrow').remove();

    // Flatten the third level: the #pro-nav toggle li becomes a subheader + its children.
    var pro = list.querySelector('#pro-nav');
    if (pro) {
      var proLi = pro.closest('li');
      var third = proLi.querySelector('ul.nav-third-level');
      var frag = document.createDocumentFragment();
      var sub = document.createElement('li');
      sub.className = 'cl-sidebar-flyout__subheader';
      sub.textContent = pro.textContent.trim();
      frag.appendChild(sub);
      if (third) {
        Array.prototype.slice.call(third.children).forEach(function (child) {
          child.classList.add('cl-sidebar-flyout__nested');
          frag.appendChild(child);
        });
      }
      proLi.replaceWith(frag);
    }
    $(list).find('[id]').removeAttr('id'); // no duplicate ids from the clone

    flyout.appendChild(list);
    document.body.appendChild(flyout);
    return flyout;
  }

  function flyoutOpen() {
    return !!(flyout && flyout.classList.contains('show'));
  }

  function openFlyout(manage) {
    var el = buildFlyout();
    if (!el) { return; }
    // DISABLE (not just hide) the trigger's tooltip while the flyout is open: the pointer is
    // still hovering the cogs, so a plain hide() gets re-shown by the hover trigger and the
    // pill sits over the flyout title. closeFlyout re-arms it.
    var tip = bootstrap.Tooltip.getInstance(manage);
    if (tip) { tip.disable(); tip.hide(); }

    el.classList.add('show');
    var railRect = document.querySelector('nav.navbar-static-side').getBoundingClientRect();
    var manageRect = manage.getBoundingClientRect();
    el.style.left = Math.round(railRect.right + 4) + 'px';
    var top = Math.min(Math.max(Math.round(manageRect.top), 12),
                       Math.max(12, window.innerHeight - el.offsetHeight - 12));
    el.style.top = top + 'px';

    manage.setAttribute('aria-expanded', 'true');
    var first = el.querySelector('a[href]');
    if (first) { first.focus(); }
  }

  function closeFlyout(refocus) {
    if (!flyoutOpen()) { return; }
    flyout.classList.remove('show');
    var manage = document.getElementById('manage');
    if (manage) {
      manage.setAttribute('aria-expanded', 'false');
      var tip = bootstrap.Tooltip.getInstance(manage);
      if (tip && isDesktopMini()) { tip.enable(); } // re-arm the tooltip the open disabled
      if (refocus) { manage.focus(); }
    }
  }

  // THE GATE — capture phase on document runs strictly before metisMenu's anchor-bound handler.
  document.addEventListener('click', function (e) {
    var manage = e.target.closest && e.target.closest('#manage');
    if (!manage || !e.isTrusted) { return; } // synthetic common.js click stays with metisMenu
    if (!isDesktopMini()) { return; }        // expanded + mobile: metisMenu keeps owning it
    e.preventDefault();
    e.stopPropagation();
    if (flyoutOpen()) { closeFlyout(false); } else { openFlyout(manage); }
  }, true);

  // Dismissal: outside click closes; a click INSIDE closes on the next tick (the navigation or
  // the Programs modal data-api fires first — never preventDefault here).
  document.addEventListener('click', function (e) {
    if (!flyoutOpen()) { return; }
    var closest = e.target.closest ? e.target : e.target.parentElement;
    if (!closest) { return closeFlyout(false); }
    if (closest.closest('.cl-sidebar-flyout')) {
      setTimeout(function () { closeFlyout(false); }, 0);
    } else if (!closest.closest('#manage')) {
      closeFlyout(false);
    }
  });

  // Keyboard: Escape closes + refocuses the trigger; arrows cycle the links.
  document.addEventListener('keydown', function (e) {
    if (!flyoutOpen()) { return; }
    if (e.key === 'Escape') { e.preventDefault(); closeFlyout(true); return; }
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') { return; }
    var links = Array.prototype.slice.call(flyout.querySelectorAll('a[href]'));
    if (!links.length) { return; }
    e.preventDefault();
    var idx = links.indexOf(document.activeElement);
    var next = e.key === 'ArrowDown' ? (idx + 1) % links.length
                                     : (idx - 1 + links.length) % links.length;
    links[next].focus();
  });

  // Focus leaving the panel (tab-out) closes it.
  document.addEventListener('focusin', function (e) {
    if (!flyoutOpen()) { return; }
    if (!e.target.closest) { return; }
    if (!e.target.closest('.cl-sidebar-flyout') && !e.target.closest('#manage')) {
      closeFlyout(false);
    }
  });

  // A fixed panel must not drift from its anchor: close on viewport scroll/resize.
  // (Scrolling INSIDE the flyout's own overflow is fine — guard it.)
  window.addEventListener('resize', function () { closeFlyout(false); });
  document.addEventListener('scroll', function (e) {
    if (!flyoutOpen()) { return; }
    if (flyout.contains(e.target)) { return; }
    closeFlyout(false);
  }, true);

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
    syncMiniAffordances();
  }
  syncBodySmall();
  $(window).on('resize', syncBodySmall);

  // C1 — nav tooltips for the icon-only rail. Created ONCE from each top-level link's own
  // .nav-label text (no title=/data-bs-title in the HAML: a title attribute would double up
  // as a native tooltip, and the declarative initializer below would double-manage a
  // data-bs-toggle). container:body escapes the rail's overflow-x:hidden (body has no
  // transform on desktop). Enabled only in desktop-mini via syncMiniAffordances above.
  // The selector's `> li > a` shape naturally skips the .nav-header profile anchors.
  $('#side-menu > li > a').each(function () {
    var label = $(this).find('.nav-label').text().trim();
    if (!label) { return; }
    navTooltips.push(new bootstrap.Tooltip(this, {
      title: label,
      placement: 'right',
      container: 'body',
      customClass: 'cl-nav-tooltip',
      trigger: 'hover focus',
      offset: [0, 6]
    }));
  });
  syncMiniAffordances();

  // Sidebar accordion (nested .nav-second-level / .nav-third-level).
  $('#side-menu').metisMenu();

  // Minimalize (hamburger) — collapse the sidebar to an icon rail. Desktop toggles persist.
  $('.navbar-minimalize').on('click', function (e) {
    e.preventDefault();
    $('body').toggleClass('mini-navbar');
    if (!$('body').hasClass('body-small')) {
      persistSidebar($('body').hasClass('mini-navbar') ? 'mini' : 'full');
    }
    syncMiniAffordances(); // C1: arm/disarm the rail tooltips with the state change
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
