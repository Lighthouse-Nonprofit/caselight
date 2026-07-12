const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  let current = '';
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(`${current}: ${m.text().slice(0, 160)}`); });
  page.on('pageerror', (e) => errors.push(`${current}: [pageerror] ${String(e).slice(0, 200)}`));
  const base = 'http://cases.lvh.me:3001';

  current = 'login';
  await page.goto(`${base}/users/sign_in`, { waitUntil: 'networkidle' });
  await page.fill('input[name="user[email]"]', 'demo.admin@caselight.test');
  await page.fill('input[name="user[password]"]', 'Caselight!Demo2026');
  await page.click('button[type="submit"], input[type="submit"]');
  await page.waitForLoadState('networkidle');

  // AccessLog write (AccessAudit after_action on client show) + ClientHistory write (client save)
  current = '/clients/cases-1 show';
  const r1 = await page.goto(`${base}/clients/cases-1`, { waitUntil: 'networkidle' });
  console.log('client show:', r1.status());

  current = 'client edit+save';
  await page.goto(`${base}/clients/cases-1/edit`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(800);
  const noteSel = 'form#edit_client_cases-1, form[id^="edit_client"]';
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'networkidle', timeout: 45000 }),
    page.evaluate(() => document.querySelector('form[id^="edit_client"]').submit()),
  ]).catch(() => {});
  console.log('client save url:', page.url().includes('/clients/') ? 'OK' : page.url());

  // TaskHistory write via task pages; windowed AccessLog reads
  for (const p of ['/tasks', '/admin/access_review', '/admin/enforcement_settings']) {
    current = p;
    const r = await page.goto(`${base}${p}`, { waitUntil: 'networkidle' });
    console.log(p, '->', r.status());
    await page.waitForTimeout(500);
  }

  console.log('\n=== console/page errors:', errors.length);
  errors.slice(0, 10).forEach((e) => console.log(' ', e));
  await browser.close();
})();
