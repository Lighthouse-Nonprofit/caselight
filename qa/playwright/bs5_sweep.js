// bs5_sweep.js — the POAM-017g visual + console gate (BS5-P6).
//
// Sweeps ~32 authenticated surfaces, captures a full-page screenshot per surface, runs
// framework-agnostic DOM assertions (selector UNIONS so the same script passes on the BS3
// baseline and the BS5 candidate), collects console/page errors against a known-noise
// allowlist, and emits a side-by-side contact sheet (compare.html) when both a baseline
// and a candidate directory exist.
//
// Usage:
//   node qa/playwright/bs5_sweep.js --out ~/caselight-evidence/poam-017g/baseline-<sha>
//   node qa/playwright/bs5_sweep.js --out .../candidate-<sha> --compare .../baseline-<sha>
//
// Login uses the SEEDED DEV demo admin (synthetic tenant data only; never a real account).
// Override with QA_EMAIL / QA_PASSWORD / QA_BASE env vars.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = process.env.QA_BASE || 'http://cases.lvh.me:3001';
const EMAIL = process.env.QA_EMAIL || 'demo.admin@caselight.test';
const PASSWORD = process.env.QA_PASSWORD || 'Caselight!Demo2026';

const argv = process.argv.slice(2);
const arg = (name) => {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : null;
};
const OUT = arg('--out');
const COMPARE = arg('--compare');
if (!OUT) { console.error('missing --out <dir>'); process.exit(2); }
fs.mkdirSync(OUT, { recursive: true });

// Known pre-existing noise (present since before the BS5 program; label + fragment match).
const CONSOLE_ALLOWLIST = [
  { label: /users-index|user-new|settings/, text: /404/ },
];

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const errors = [];
  const failures = [];
  let current = 'init';
  page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const text = m.text();
    if (text.includes('favicon')) return;
    if (CONSOLE_ALLOWLIST.some((a) => a.label.test(current) && a.text.test(text))) return;
    errors.push(`[${current}] ${text.slice(0, 160)}`);
  });
  page.on('pageerror', (e) => errors.push(`[${current}] PAGEERROR ${String(e).slice(0, 160)}`));

  const shoot = async (label) => {
    await page.screenshot({ path: path.join(OUT, `${label}.png`), fullPage: true });
  };

  // Framework-agnostic per-surface assertions (BS3/BS5 union selectors).
  const assertSurface = async (label, opts = {}) => {
    const r = await page.evaluate(() => {
      const vis = (el) => !!el && el.getBoundingClientRect().height > 0;
      const body = getComputedStyle(document.body);
      return {
        sidebar: vis(document.querySelector('#side-menu, .cl-sidebar, nav.navbar-static-side')),
        topnav: vis(document.querySelector('.navbar-static-top, .cl-topnav, nav.navbar')),
        themed: body.backgroundColor !== 'rgba(0, 0, 0, 0)' && body.backgroundColor !== 'rgb(255, 255, 255)'
          ? true : !!document.querySelector('#wrapper, #page-wrapper'),
        // the BODY font is deliberately the system-UI stack; the regression signal is the
        // self-hosted Open Sans FACE being available (12C-1 self-host)
        fontOk: document.fonts && document.fonts.check('16px "Open Sans"'),
        containers: document.querySelectorAll('.ibox, .card').length,
        hOverflow: document.documentElement.scrollWidth > window.innerWidth + 1,
        contentH: (document.querySelector('#page-wrapper, main') || document.body)
          .getBoundingClientRect().height,
        formControls: document.querySelectorAll('input.form-control, select.form-control, textarea.form-control, input.form-check-input').length,
      };
    });
    const problems = [];
    if (!opts.noShell) {
      if (!r.sidebar) problems.push('sidebar missing');
      if (!r.topnav) problems.push('topnav missing');
      if (!r.fontOk) problems.push('Open Sans face not loaded');
      if (r.contentH < 300) problems.push(`content height ${Math.round(r.contentH)}px`);
      if (!opts.noContainers && r.containers === 0) problems.push('no .ibox/.card containers');
    }
    if (r.hOverflow) problems.push('horizontal overflow');
    if (opts.form && r.formControls === 0) problems.push('no form controls');
    if (problems.length) failures.push(`[${label}] ${problems.join('; ')}`);
  };

  const go = async (pathname, label, opts = {}) => {
    current = label;
    try {
      await page.goto(`${BASE}${pathname}`, { waitUntil: 'networkidle', timeout: 30000 });
      await page.waitForTimeout(700);
      await assertSurface(label, opts);
      await shoot(label);
    } catch (e) {
      failures.push(`[${label}] NAV-FAIL ${String(e).slice(0, 120)}`);
    }
  };

  // ---- login (also screenshotted, shell-less) ----
  current = 'login';
  await page.goto(`${BASE}/users/sign_in`, { waitUntil: 'networkidle' });
  await shoot('login');
  await page.fill('#user_email', EMAIL);
  await page.fill('#user_password', PASSWORD);
  await page.click('input[type="submit"], button[type="submit"]');
  await page.waitForLoadState('networkidle');

  // ---- core sweep ----
  await go('/', 'dashboard');
  await go('/clients', 'clients-index');

  // NB dev appends ?locale=en to every href (strip it) and /clients/new matches the slug
  // pattern (exclude it)
  const clientPath = await page.evaluate(() =>
    Array.from(document.querySelectorAll('a[href*="/clients/"]'))
      .map((a) => (a.getAttribute('href') || '').split('?')[0])
      .find((h) => /\/clients\/(?!new$)[a-z0-9-]+$/i.test(h)));
  if (!clientPath) failures.push('[client-extraction] no client link found on /clients');
  if (clientPath) {
    await go(clientPath, 'client-show');
    // dropdown-open shot: silent-failure surface for the data-bs rename
    try {
      const toggle = await page.$('[data-toggle="dropdown"], [data-bs-toggle="dropdown"]');
      if (toggle) {
        await toggle.click();
        await page.waitForTimeout(400);
        await shoot('client-show-menus-open');
      }
    } catch (e) { failures.push(`[client-show-menus-open] ${String(e).slice(0, 100)}`); }
    await go(`${clientPath}/edit`, 'client-edit', { form: true });
    await go(`${clientPath}/case_notes/new`, 'case-note-new', { form: true });
    await go(`${clientPath}/assessments/new`, 'assessment-new', { form: true, noContainers: true });
  }
  await go('/clients/new', 'client-new-wizard', { form: true });
  await go('/families', 'families-index');
  await go('/families/new', 'family-new', { form: true });
  await go('/tasks', 'tasks', { noContainers: true });
  await go('/calendars', 'calendar', { noContainers: true });
  await go('/custom_fields', 'custom-fields-index');
  await go('/custom_fields/new', 'form-builder-new', { form: true });
  await go('/client_advanced_searches', 'advanced-search');
  await go('/programs', 'program-streams-index');
  // tab second states hide broken panes — shoot both
  try {
    const tab2 = await page.$('a[href="#ngos-program-streams"]');
    if (tab2) { await tab2.click(); await page.waitForTimeout(500); await shoot('program-streams-index-tab2'); }
  } catch (e) {}
  await go('/programs/new', 'program-stream-new', { form: true });
  const psShow = await page.evaluate(() =>
    Array.from(document.querySelectorAll('a[href*="/programs/"]'))
      .map((a) => (a.getAttribute('href') || '').split('?')[0])
      .find((h) => /\/programs\/\d+$/.test(h)));
  await go('/domains', 'domains');
  await go('/admin/users', 'users-index');
  await go('/admin/users/new', 'user-new', { form: true });
  await go('/users/edit', 'account-edit', { form: true });
  await go('/admin/enforcement_settings', 'enforcement-settings');
  await go('/admin/access_review', 'access-review', { noContainers: true });
  await go('/partners', 'partners');
  await go('/agencies', 'agencies');
  await go('/changelogs', 'changelogs');
  if (psShow) await go(psShow, 'program-stream-show');
  await go('/custom_fields', 'custom-fields-index-tabs');
  try {
    const cfTab = await page.$('a[href="#all-custom-form"]');
    if (cfTab) { await cfTab.click(); await page.waitForTimeout(500); await shoot('custom-fields-index-tab2'); }
  } catch (e) {}

  // ---- report ----
  console.log('===== assertion failures:', failures.length);
  failures.forEach((f) => console.log('  ' + f));
  console.log('===== console/page errors (non-allowlisted):', errors.length);
  errors.slice(0, 20).forEach((e) => console.log('  ' + e));

  // ---- contact sheet ----
  if (COMPARE && fs.existsSync(COMPARE)) {
    const labels = fs.readdirSync(OUT).filter((f) => f.endsWith('.png')).sort();
    const rows = labels.map((f) => {
      const b = path.join(COMPARE, f);
      const left = fs.existsSync(b) ? `<img src="${b}" loading="lazy">` : '<em>(no baseline)</em>';
      return `<tr><th colspan="2">${f.replace('.png', '')}</th></tr>
<tr><td>${left}</td><td><img src="${path.join(OUT, f)}" loading="lazy"></td></tr>`;
    }).join('\n');
    const html = `<!doctype html><meta charset="utf-8"><title>BS3 vs BS5 — POAM-017g</title>
<style>table{border-collapse:collapse}td{border:1px solid #ccc;vertical-align:top;width:50%}img{max-width:680px;display:block}th{background:#eee;text-align:left;padding:6px;font-family:sans-serif}</style>
<p>Left: baseline (${COMPARE}) — Right: candidate (${OUT}).</p>
<p>Checklist per pair: shell themed · no unstyled region · no overlap/clip · forms aligned · tables intact · deltas intended-only · polish alive on show pages.</p>
<table>${rows}</table>`;
    fs.writeFileSync(path.join(OUT, 'compare.html'), html);
    console.log('contact sheet:', path.join(OUT, 'compare.html'));
  }

  await browser.close();
  process.exit(failures.length || errors.length ? 1 : 0);
})().catch((e) => { console.error('SWEEP FAIL', e); process.exit(2); });
