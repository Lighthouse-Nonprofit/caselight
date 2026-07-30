// bs5_interactions.js — the POAM-017g SILENT-FAILURE gate (BS5-P6).
//
// The data-toggle -> data-bs-* rename and the bootstrap-sprockets -> vanilla-BS5 swap break
// interactive components WITHOUT console errors: modals/dropdowns/collapses/tabs/popovers
// simply stop opening. This script exercises one representative of every class and asserts
// the visible outcome. Selector UNIONS keep it runnable on both the BS3 baseline and the
// BS5 candidate. Exits non-zero on any FAIL.
//
// Usage: node qa/playwright/bs5_interactions.js
const { chromium } = require('playwright');

const BASE = process.env.QA_BASE || 'http://cases.lvh.me:3001';
const EMAIL = process.env.QA_EMAIL || 'demo.admin@caselight.test';
const PASSWORD = process.env.QA_PASSWORD || 'Caselight!Demo2026';

const results = [];
const block = async (name, fn) => {
  try {
    await fn();
    results.push(['PASS', name]);
  } catch (e) {
    results.push(['FAIL', `${name} — ${String(e.message || e).slice(0, 140)}`]);
  }
};

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  // ANY matching element visible (page.$ alone would test only the first match)
  const visible = (sel) => page.evaluate((s) =>
    Array.from(document.querySelectorAll(s)).some((el) => el.getBoundingClientRect().height > 0), sel);
  const goto = async (p) => {
    await page.goto(`${BASE}${p}`, { waitUntil: 'networkidle', timeout: 30000 });
    await page.waitForTimeout(500);
  };
  // dev appends ?locale=en to hrefs — strip the query before matching
  const firstPath = (containsFragment, pattern) => page.evaluate(({ frag, pat }) =>
    Array.from(document.querySelectorAll(`a[href*="${frag}"]`))
      .map((a) => (a.getAttribute('href') || '').split('?')[0])
      .find((h) => new RegExp(pat, 'i').test(h)),
    { frag: containsFragment, pat: pattern });
  const clientPathOnce = async () => {
    await goto('/clients');
    // exclude the /clients/new "add" link — 'new' matches the slug pattern
    const p = await firstPath('/clients/', '/clients/(?!new$)[a-z0-9-]+$');
    if (!p) throw new Error('no client link on /clients');
    return p;
  };

  await page.goto(`${BASE}/users/sign_in`, { waitUntil: 'networkidle' });
  await page.fill('#user_email', EMAIL);
  await page.fill('#user_password', PASSWORD);
  await page.click('input[type="submit"], button[type="submit"]');
  await page.waitForLoadState('networkidle');

  // 1. Declarative modal (+ dismiss)
  await block('declarative-modal (/agencies)', async () => {
    await goto('/agencies');
    await page.click('[data-toggle="modal"], [data-bs-toggle="modal"]');
    await page.waitForTimeout(600);
    if (!(await visible('.modal.in, .modal.show'))) throw new Error('modal did not open');
    await page.click('.modal.in [data-dismiss="modal"], .modal.show [data-bs-dismiss="modal"], .modal.show .btn-close, .modal.in button.close');
    await page.waitForTimeout(600);
    if (await visible('.modal.in, .modal.show')) throw new Error('modal did not dismiss');
  });

  // 2. JS-opened modal (calendar day click)
  await block('js-modal (calendar day-click)', async () => {
    await goto('/calendars');
    await page.waitForTimeout(1200);
    await page.click('.fc-daygrid-day', { position: { x: 20, y: 20 } });
    await page.waitForTimeout(800);
    if (!(await visible('.modal.in, .modal.show'))) throw new Error('task modal did not open');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(400);
  });

  // 3. Topnav dropdowns (account + notifications)
  await block('dropdowns (account + notifications)', async () => {
    await goto('/tasks');
    await page.click('.navbar-top-links a.dropdown-toggle, .cl-topnav a.dropdown-toggle');
    await page.waitForTimeout(400);
    if (!(await visible('.dropdown-menu'))) throw new Error('account dropdown did not open');
    await page.keyboard.press('Escape');
    const notif = await page.$('a.count-info');
    if (notif) {
      await notif.click();
      await page.waitForTimeout(400);
      if (!(await visible('.dropdown-menu'))) throw new Error('notifications dropdown did not open');
      await page.keyboard.press('Escape');
    }
  });

  // 4. Collapse (clients search filters) — assert on the class flip (in/show), which is
  // framework-versioned but animation-independent
  await block('collapse (clients search filters)', async () => {
    await goto('/clients');
    const stateOf = () => page.evaluate(() => {
      const t = document.querySelector('#client-search-form');
      return t ? { cls: t.className, h: t.getBoundingClientRect().height } : null;
    });
    const before = await stateOf();
    if (!before) throw new Error('#client-search-form missing');
    await page.click('button.btn-filter[data-toggle="collapse"], button.btn-filter[data-bs-toggle="collapse"]');
    await page.waitForTimeout(900);
    const after = await stateOf();
    const opened = (/(^|\s)(in|show)(\s|$)/.test(after.cls) && !/(^|\s)(in|show)(\s|$)/.test(before.cls)) || after.h > before.h;
    if (!opened) throw new Error(`collapse did not open (cls '${before.cls}' -> '${after.cls}', h ${before.h} -> ${after.h})`);
  });

  // 5. Tabs (declarative + the converted JS .tab sites). Q1 hardening: activating the new
  // pane is NOT enough — the flip shipped li.active markup where BS5's Tab couldn't find
  // the previous trigger, so the OLD pane stayed visible and both stacked. Assert the old
  // pane deactivates and the highlight moves too.
  await block('tabs (program_streams + custom_fields)', async () => {
    const switchAndAssert = async (clickSel, newPane, oldPane) => {
      await page.click(clickSel);
      await page.waitForTimeout(500);
      if (!(await visible(newPane))) throw new Error(`${newPane} not shown`);
      if (await visible(oldPane)) throw new Error(`${oldPane} still visible after switching away (both panes stacked)`);
      const linkActive = await page.$eval(clickSel, (a) => a.classList.contains('active') || a.parentElement.classList.contains('active'));
      if (!linkActive) throw new Error(`trigger ${clickSel} did not take the active highlight`);
    };
    await goto('/programs');
    await switchAndAssert('a[href="#ngos-program-streams"]', '#ngos-program-streams', '#current-program-streams');
    await goto('/custom_fields');
    await switchAndAssert('a[href="#all-custom-form"]', '#all-custom-form', '#custom-form');
  });

  // 6. Popover — RE-BASELINED (investor UX round): the family-show member grid went LEAN and
  // no longer renders popover columns; the full ClientGrid (form-title "Total : N" popover)
  // lives on the advanced-search surface now.
  // RE-BASELINED (investor UX round): the popover COLUMNS left the default pages (family-show
  // members + users-caseload grids went lean; the full grid renders only on a submitted
  // advanced search). SYNTHETIC check (toastr pattern): the BS5 popover API itself stays
  // covered without depending on a redesigned surface.
  await block('popover (synthetic, BS5 API)', async () => {
    await goto('/');
    const shown = await page.evaluate(async () => {
      const btn = document.createElement('button');
      btn.setAttribute('data-bs-toggle', 'popover');
      btn.setAttribute('data-bs-content', 'qa-popover-body');
      btn.textContent = 'qa-popover';
      document.body.appendChild(btn);
      const pop = new window.bootstrap.Popover(btn);
      pop.show();
      await new Promise((r) => setTimeout(r, 600));
      return !!document.querySelector('.popover');
    });
    if (!shown) throw new Error('synthetic BS5 popover did not open');
  });

  // 7. Datepicker opens + picks. FORMAT PIN: the app configures format 'yyyy-mm-dd' at every
  // site (P6 audit) — the ISO shape, NOT locale dd/mm/yyyy. The BS5 replacement must keep it.
  await block('datepicker (open + pick, yyyy-mm-dd)', async () => {
    const clientPath = await clientPathOnce();
    await goto(`${clientPath}/edit`);
    const dateInput = await page.$('input.datepicker, .date input, input[data-provide="datepicker"], input[name*="date"]');
    if (!dateInput) throw new Error('no date input on client edit');
    await dateInput.click();
    await page.waitForTimeout(600);
    const open = await visible('.datepicker.dropdown-menu, .datepicker-dropdown.active, .datepicker-dropdown');
    if (!open) throw new Error('datepicker did not open');
    await page.click('.datepicker td.day:not(.old):not(.new), .datepicker-dropdown .datepicker-cell:not(.prev):not(.next)');
    await page.waitForTimeout(300);
    const val = await dateInput.inputValue();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(val)) throw new Error(`picked value '${val}' not yyyy-mm-dd`);
  });

  // 8. fileinput (krajee) renders + accepts a file
  await block('fileinput (case-note form)', async () => {
    const clientPath = await clientPathOnce();
    await goto(`${clientPath}/case_notes/new`);
    const wrap = await page.$('.file-input, .file-input-new, .btn-file');
    if (!wrap) throw new Error('fileinput widget not rendered');
    const input = await page.$('input[type="file"].file, .file-input input[type="file"], input[type="file"]');
    if (input) {
      await input.setInputFiles({ name: 'gate.txt', mimeType: 'text/plain', buffer: Buffer.from('bs5 gate') });
      await page.waitForTimeout(600);
      const caption = await page.evaluate(() => {
        const c = document.querySelector('.file-caption-name, .file-caption .file-caption-name, .file-preview');
        return c ? (c.textContent || c.getAttribute('title') || '') : '';
      });
      if (!/gate\.txt|1 file|file selected/i.test(caption) && caption.length === 0) {
        throw new Error('picked file not reflected in caption/preview');
      }
    }
  });

  // 9. D2: jquery.dataTables is GONE — the users grid now scrolls natively inside
  // .cl-table-scroll with a position:sticky thead (CIF.RecordTable). Assert the NEW
  // contract: wrapper class applied, sticky header computed, rows present, and no
  // dataTables artifact anywhere.
  await block('native table scroll (/admin/users)', async () => {
    await goto('/admin/users');
    const r = await page.evaluate(() => {
      const th = document.querySelector('.cl-table-scroll table thead th, .cl-table-scroll > table thead th');
      return {
        wrapper: !!document.querySelector('.users-table.cl-table-scroll'),
        sticky: th ? getComputedStyle(th).position : 'missing',
        rows: document.querySelectorAll('table.users tbody tr').length,
        dtArtifact: !!document.querySelector('table.dataTable, .dataTables_wrapper, .dataTables_scrollBody'),
      };
    });
    if (!r.wrapper) throw new Error('.users-table did not get .cl-table-scroll');
    if (r.sticky !== 'sticky') throw new Error('users thead th is not position:sticky (got ' + r.sticky + ')');
    if (r.rows === 0) throw new Error('no rows in the users table');
    if (r.dtArtifact) throw new Error('a dataTables artifact survived the D2 removal');
  });

  // 10. Wizard INITIALIZES (jquery.steps on assessments — P6 probe; clients/new has no
  // wizard). Advancing is validation-gated (unscored domains refuse #next by design), and
  // jquery.steps is KEPT at the flip (css restyle only) — so the gate asserts the steps
  // chrome rendered and #next responds without throwing.
  await block('wizard init (assessment steps)', async () => {
    // A client whose next review is not yet due redirects /assessments/new to the history
    // page ("Begin now" renders as a disabled div — data-dependent, not a wizard defect).
    // Try several clients and assert the wizard on the first one that can start an assessment.
    await goto('/clients');
    const clientPaths = await page.evaluate(() =>
      Array.from(document.querySelectorAll('a[href*="/clients/"]'))
        .map((a) => (a.getAttribute('href') || '').split('?')[0])
        .filter((h, i, all) => /\/clients\/(?!new$)[a-z0-9-]+$/i.test(h) && all.indexOf(h) === i));
    let r = { stepItems: 0, next: false, current: false };
    for (const cp of clientPaths.slice(0, 8)) {
      await goto(`${cp}/assessments/new`);
      r = await page.evaluate(() => ({
        stepItems: document.querySelectorAll('.steps li').length,
        next: !!document.querySelector('a[href="#next"]'),
        current: !!document.querySelector('.steps li.current'),
      }));
      if (r.stepItems >= 2 && r.next && r.current) break;
    }
    if (r.stepItems < 2 || !r.next || !r.current) {
      throw new Error(`wizard chrome incomplete on every probed client (steps=${r.stepItems} next=${r.next} current=${r.current})`);
    }
    await page.click('a[href="#next"]');
    await page.waitForTimeout(500);
    const alive = await page.evaluate(() => !!document.querySelector('.steps li.current'));
    if (!alive) throw new Error('wizard broke on #next click');
  });

  // 11. Checkboxes visible + toggle (iCheck today, form-check after flip)
  // 11. Checkboxes visible + toggling — via the clients column picker (open the filter
  // collapse, open the picker dropdown, toggle a column checkbox). Compound coverage:
  // collapse + in-form dropdown + the iCheck/form-check control in one flow.
  await block('checkboxes (clients column picker)', async () => {
    await goto('/clients');
    await page.click('button.btn-filter[data-toggle="collapse"], button.btn-filter[data-bs-toggle="collapse"]');
    await page.waitForTimeout(900);
    await page.click('#client-search-form a.dropdown-toggle, #client-search-form [data-bs-toggle="dropdown"]');
    await page.waitForTimeout(500);
    const state = await page.evaluate(() => {
      const menu = Array.from(document.querySelectorAll('.dropdown-menu'))
        .find((m) => m.getBoundingClientRect().height > 0 && m.querySelector('input[type="checkbox"]'));
      if (!menu) return { found: false };
      const input = menu.querySelector('input[type="checkbox"]');
      const wrapper = input.closest('[class*="icheckbox"], .form-check') || input;
      const box = wrapper.getBoundingClientRect();
      input.id = input.id || 'bs5-gate-cb';
      wrapper.id = wrapper.id || 'bs5-gate-wrap';
      return { found: true, id: input.id, wrapId: wrapper.id, visibleBox: box.height > 0 && box.width > 0, checked: input.checked };
    });
    if (!state.found) throw new Error('no open dropdown menu with checkboxes');
    if (!state.visibleBox) throw new Error('checkbox control has no visible box (orphaned styling)');
    // REAL mouse click: iCheck's handler sits on the ins.iCheck-helper overlay, which a
    // synthetic DOM .click() on the wrapper never reaches
    await page.click(`#${state.wrapId}`, { force: true });
    await page.waitForTimeout(400);
    const toggled = await page.evaluate((id) => document.getElementById(id).checked, state.id);
    if (toggled === state.checked) throw new Error('checkbox did not toggle');
  });

  // 12. Tom Select opens
  await block('tom-select (client edit)', async () => {
    const clientPath = await clientPathOnce();
    await goto(`${clientPath}/edit`);
    const ts = await page.$('.ts-control');
    if (!ts) throw new Error('no Tom Select on client edit');
    await ts.click();
    await page.waitForTimeout(400);
    if (!(await visible('.ts-dropdown'))) throw new Error('ts-dropdown did not open');
  });

  // 13. toastr fires visibly (BS5 .toast CSS collision check)
  await block('toastr (synthetic, opacity)', async () => {
    await goto('/tasks');
    await page.evaluate(() => window.toastr && window.toastr.success('bs5-gate'));
    await page.waitForTimeout(600);
    const op = await page.evaluate(() => {
      const t = document.querySelector('#toast-container .toast');
      return t ? parseFloat(getComputedStyle(t).opacity) : -1;
    });
    if (op < 0) throw new Error('toast element missing');
    if (op < 0.5) throw new Error(`toast opacity ${op} — BS5 .toast CSS collision?`);
  });

  // 14. Flash round-trip on a real save
  await block('flash round-trip (client save)', async () => {
    const clientPath = await clientPathOnce();
    await goto(`${clientPath}/edit`);
    // the visible save control is button.form-btn (the type=submit input is hidden)
    await page.click('button.form-btn, input[type="submit"]:visible, button[type="submit"]:visible');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(800);
    const ok = await page.evaluate(() =>
      !!document.querySelector('#toast-container .toast, .alert-success, .alert.alert-dismissible') ||
      !/\/edit$/.test(location.pathname));
    if (!ok) throw new Error('no flash/redirect after save');
  });

  console.log('===== interaction gate =====');
  for (const [status, name] of results) console.log(`  ${status}  ${name}`);
  const fails = results.filter(([s]) => s === 'FAIL').length;
  console.log(`${results.length - fails}/${results.length} passed`);
  await browser.close();
  process.exit(fails ? 1 : 0);
})().catch((e) => { console.error('GATE FAIL', e); process.exit(2); });
