#!/usr/bin/env node
// Re-capture the docs screenshots (docs/screenshots/*.jpg) against a local dev instance
// on the current theme. Companion to docs/build-pdfs.js — run this first, then rebuild
// the PDFs. Synthetic demo data only (the seeded demo.* users; see DEVELOPMENT.md).
//
//   NODE_PATH=<playwright node_modules> node docs/capture-screenshots.js
//   QA_BASE=http://cases.lvh.me:3001 (default)
//
// The URL map below is the source of truth for what each image shows — keep it in sync
// with config/routes.rb (access-review is /admin/access_review, NOT /access_reviews —
// that guess once shipped a screenshot of the routing-error page).

const { chromium } = require('playwright');
const path = require('path');
const BASE = process.env.QA_BASE || 'http://cases.lvh.me:3001';
const OUT = path.join(__dirname, 'screenshots');
const PASSWORD = process.env.QA_PASSWORD || 'Caselight!Demo2026';

const SHOTS = [
  // [file, role (null = logged out), path ('@client' = first data-bearing client), width, height, opts]
  ['login.jpg', null, '/users/sign_in', 1200, 750, {}],
  ['dashboard.jpg', 'admin', '/', 1680, 1050, {}],
  ['families.jpg', 'admin', '/families', 1500, 938, {}],
  ['clients-grid.jpg', 'admin', '/clients', 1560, 975, {}],
  ['clients-grid-director.jpg', 'director', '/clients', 1500, 938, {}],
  ['clients-cards.jpg', 'worker', '/clients', 1560, 975, {}],
  ['client-detail.jpg', 'admin', '@client', 1560, 975, {}],
  ['client-forms.jpg', 'admin', '@client/forms', 1500, 938, {}],
  // household hub (UX round 3): overview w/ member list (+ alert banner when one is active),
  // plus the Notes and Alerts tabs. '@family' = first data-bearing household, probed like @client.
  ['family-detail.jpg', 'admin', '@family', 1560, 975, {}],
  ['family-notes.jpg', 'admin', '@family/family_notes', 1500, 938, {}],
  ['family-alerts.jpg', 'admin', '@family/family_alerts', 1500, 938, {}],
  ['programs.jpg', 'admin', '/program_streams', 1500, 938, {}],
  ['client-programs.jpg', 'admin', '@client/client_enrollments', 1500, 938, {}],
  ['case-notes.jpg', 'admin', '@client/case_notes', 1500, 938, {}],
  ['case-note-form.jpg', 'admin', '@client/case_notes/new', 1500, 1100, {}],
  ['tasks.jpg', 'admin', '/tasks', 1560, 975, {}],
  ['domains.jpg', 'admin', '/domains', 1500, 938, {}],
  ['calendar.jpg', 'admin', '/calendars', 1560, 975, {}],
  ['form-builder.jpg', 'admin', '/custom_fields/new', 1400, 1032, {}],
  ['access-review.jpg', 'admin', '/admin/access_review', 1680, 1050, {}],
  ['enforcement.jpg', 'admin', '/admin/enforcement_settings', 1300, 900, { fullPage: true }],
  ['manage-users.jpg', 'admin', '/admin/users', 1360, 595, {}],
  ['manage-agencies.jpg', 'admin', '/agencies', 1360, 595, {}],
  ['manage-departments.jpg', 'admin', '/departments', 1360, 595, {}],
  ['manage-domain-groups.jpg', 'admin', '/domain_groups', 1360, 595, {}],
  ['manage-donors.jpg', 'admin', '/donors', 1360, 595, {}],
  ['manage-progress-note-types.jpg', 'admin', '/progress_note_types', 1360, 595, {}],
  ['manage-quantitative-types.jpg', 'admin', '/quantitative_types', 1360, 595, {}],
  ['manage-referral-sources.jpg', 'admin', '/referral_sources', 1360, 595, {}],
  ['partners.jpg', 'admin', '/partners', 1360, 595, {}],
  ['not-found.jpg', 'admin', '/this-page-does-not-exist', 1100, 688, { allowError: true }],
];

(async () => {
  const browser = await chromium.launch();
  const sessions = {};
  const login = async (role) => {
    if (sessions[role]) return sessions[role];
    const ctx = await browser.newContext({ viewport: { width: 1560, height: 975 } });
    const page = await ctx.newPage();
    await page.goto(`${BASE}/users/sign_in`, { waitUntil: 'networkidle' });
    await page.fill('#user_email', `demo.${role}@caselight.test`);
    await page.fill('#user_password', PASSWORD);
    await page.click('input[type="submit"], button[type="submit"]');
    await page.waitForLoadState('networkidle');
    sessions[role] = ctx;
    return ctx;
  };

  const adminCtx = await login('admin');
  const probe = await adminCtx.newPage();
  await probe.goto(`${BASE}/clients`, { waitUntil: 'networkidle' });
  const clientPath = await probe.evaluate(() =>
    Array.from(document.querySelectorAll('a[href*="/clients/"]'))
      .map((a) => (a.getAttribute('href') || '').split('?')[0])
      .find((h) => /\/clients\/(?!new$)[a-z0-9-]+$/i.test(h)));
  await probe.goto(`${BASE}/families`, { waitUntil: 'networkidle' });
  const familyPath = await probe.evaluate(() =>
    Array.from(document.querySelectorAll('a[href*="/families/"]'))
      .map((a) => (a.getAttribute('href') || '').split('?')[0])
      .find((h) => /\/families\/(?!new$)\d+$/i.test(h)));
  await probe.close();
  console.log('client for detail shots:', clientPath);
  console.log('family for hub shots:', familyPath);

  let failures = 0;
  for (const [file, role, rawPath, w, h, opts] of SHOTS) {
    const p = rawPath.replace('@client', clientPath).replace('@family', familyPath);
    const ctx = role === null
      ? await browser.newContext({ viewport: { width: w, height: h } })
      : await login(role);
    const page = await ctx.newPage();
    await page.setViewportSize({ width: w, height: h });
    await page.goto(`${BASE}${p}`, { waitUntil: 'networkidle', timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(1200);
    // refuse to ship error pages (the 404 shot is the deliberate exception)
    const bad = await page.evaluate(() => /Routing Error|Exception caught|Template is missing/i.test(document.body.innerText.slice(0, 300)));
    if (bad && !opts.allowError) {
      console.error(`ERROR PAGE at ${p} — not saving ${file}`);
      failures += 1;
    } else {
      await page.screenshot({ path: path.join(OUT, file), type: 'jpeg', quality: 82, fullPage: !!opts.fullPage });
      console.log('shot', file);
    }
    await page.close();
    if (role === null) await ctx.close();
  }
  await browser.close();
  if (failures) { console.error(`${failures} surface(s) refused`); process.exit(1); }
  console.log('ALL DONE');
})();
