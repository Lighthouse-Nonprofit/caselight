const { chromium } = require('playwright');
const { execSync } = require('child_process');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  let current = '';
  const errors = [];
  page.on('console', (m) => {
    const t = m.text();
    if (m.type() === 'error' && !t.includes('JQMIGRATE')) errors.push(`${current}: ${t.slice(0, 180)}`);
  });
  page.on('pageerror', (e) => errors.push(`${current}: [pageerror] ${String(e).slice(0, 200)}`));
  const base = 'http://cases.lvh.me:3001';

  // ---- 1. TOTP challenge login (a distinct layout under the policy) ----
  current = 'totp-login';
  await page.goto(`${base}/users/sign_in`, { waitUntil: 'networkidle' });
  await page.fill('input[name="user[email]"]', 'qa.totp@caselight.test');
  await page.fill('input[name="user[password]"]', 'Caselight!Totp2026');
  await page.click('button[type="submit"], input[type="submit"]');
  await page.waitForLoadState('networkidle');
  const challenge = await page.locator('input[name*="otp_attempt"]').count();
  console.log('TOTP challenge page rendered:', challenge > 0, '|', page.url());
  if (challenge > 0) {
    const otp = execSync(
      `wsl -d Ubuntu-24.04 bash -c "cd ~/caselight && docker compose exec -T app bundle exec rails runner \\"Apartment::Tenant.switch!(:cases); puts User.find_by(email: 'qa.totp@caselight.test').current_otp\\" 2>/dev/null | tail -1"`,
      { encoding: 'utf8' },
    ).trim();
    await page.fill('input[name*="otp_attempt"]', otp);
    await page.click('button[type="submit"], input[type="submit"]');
    await page.waitForLoadState('networkidle');
    console.log('TOTP login complete:', !page.url().includes('two_factor') && !page.url().includes('sign_in'));
  }
  await page.goto(`${base}/users/sign_out`, { waitUntil: 'networkidle' }).catch(() => {});
  await page.evaluate(() => { const f = document.createElement('form'); f.method = 'post'; f.action = '/users/sign_out'; const i = document.createElement('input'); i.name = '_method'; i.value = 'delete'; f.appendChild(i); const c = document.createElement('input'); c.name = 'authenticity_token'; c.value = document.querySelector('meta[name=csrf-token]')?.content || ''; f.appendChild(c); document.body.appendChild(f); f.submit(); }).catch(() => {});
  await page.waitForTimeout(800);

  // ---- back to the demo admin for the rest ----
  current = 'login';
  await page.goto(`${base}/users/sign_in`, { waitUntil: 'networkidle' });
  await page.fill('input[name="user[email]"]', 'demo.admin@caselight.test');
  await page.fill('input[name="user[password]"]', 'Caselight!Demo2026');
  await page.click('button[type="submit"], input[type="submit"]');
  await page.waitForLoadState('networkidle');

  // ---- 2. PDF download (wkhtmltopdf via the R13-fixed binary) ----
  current = 'pdf';
  const pdfResp = await page.request.get(`${base}/government_reports/1.pdf`);
  const pdfBody = await pdfResp.body();
  console.log('PDF download:', pdfResp.status(), pdfResp.headers()['content-type'],
    '| magic:', pdfBody.slice(0, 5).toString(), '| bytes:', pdfBody.length);

  // ---- 3. XLS export ----
  current = 'xls';
  await page.goto(`${base}/clients`, { waitUntil: 'networkidle' });
  const xlsBtn = page.locator('a:has-text("Export to XLS"), a[href*="xls"]').first();
  if (await xlsBtn.count()) {
    const [download] = await Promise.all([
      page.waitForEvent('download', { timeout: 30000 }),
      xlsBtn.click(),
    ]);
    console.log('XLS export download:', await download.suggestedFilename());
  } else {
    console.log('XLS button not found on /clients');
  }

  // ---- 4. Dropzone preview on a progress note ----
  current = 'dropzone';
  await page.goto(`${base}/clients/cases-1/progress_notes/new`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(900);
  const dzInput = page.locator('.dropzone input[type="file"], input.dz-hidden-input').first();
  if (await dzInput.count()) {
    await dzInput.setInputFiles({ name: 'soak.png', mimeType: 'image/png', buffer: Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex') });
    await page.waitForTimeout(900);
    const preview = await page.locator('.dz-preview').count();
    console.log('Dropzone preview tiles:', preview);
  } else {
    console.log('dropzone input not found (progress note form layout?)', page.url());
  }

  // ---- 5. Trix edit round-trip on a domain ----
  current = 'trix';
  await page.goto(`${base}/domains`, { waitUntil: 'networkidle' });
  const edit = page.locator('a[href*="/domains/"][href*="edit"]').first();
  if (await edit.count()) {
    await page.goto(`${base}${await edit.getAttribute('href')}`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(700);
    const hasTrix = await page.locator('trix-editor').count();
    console.log('trix editor present:', hasTrix > 0);
  }

  // ---- 6. infinite scroll page-2 (advanced search results) ----
  current = 'infinite-scroll';
  await page.goto(`${base}/client_advanced_searches`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(700);
  await page.evaluate(() => document.querySelector('#builder .rule-filter-container select').tomselect.setValue('status'));
  await page.waitForTimeout(500);
  const statusSel = page.locator('#builder .rule-value-container select');
  if (await statusSel.count()) {
    await page.evaluate(() => {
      const s = document.querySelector('#builder .rule-value-container select');
      (s.tomselect || { setValue: (v) => { s.value = v; } }).setValue(s.options[0].value);
    });
  }
  await page.click('#search');
  await page.waitForLoadState('networkidle');
  const rows = await page.locator('table.clients tbody tr').count();
  console.log('advanced search result rows:', rows);
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await page.waitForTimeout(1500);

  console.log('\n=== console/page errors:', errors.length);
  errors.slice(0, 10).forEach((e) => console.log(' ', e));
  await browser.close();
})();
