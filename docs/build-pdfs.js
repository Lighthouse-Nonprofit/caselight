#!/usr/bin/env node
// Build the printable PDFs from their markdown sources (docs/user-guide.md,
// docs/admin-guide.md) so the PDFs stay reproducible instead of session artifacts.
//
//   cd qa/playwright && npm install            # marked (renderer) lives with the QA deps
//   NODE_PATH=<playwright node_modules> node docs/build-pdfs.js
//
// Renders GitHub-flavored markdown -> styled HTML -> Chromium print-to-PDF (Playwright).
// Screenshots resolve relative to docs/. The brochure PDF is designed marketing collateral
// maintained separately (not markdown-sourced).

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const { marked } = require('marked');

const DOCS = __dirname;
const JOBS = [
  { src: 'user-guide.md', out: 'pdf/CaseLight-User-Guide.pdf', title: 'CaseLight — User Guide', cover: ['WORKING IN CASELIGHT', 'User Guide', 'A screen-by-screen walkthrough for staff — individuals, households, programs, assessments, case notes, and the calendar.'] },
  { src: 'admin-guide.md', out: 'pdf/CaseLight-Administrator-Guide.pdf', title: 'CaseLight — Administrator Guide', cover: ['CONFIGURING & SECURING CASELIGHT', 'Administrator Guide', 'Set up users, tailor the system to your programs without code, and operate its security controls — everything under Manage and the admin surfaces.'] },
];

const CSS = `
  * { box-sizing: border-box; }
  body { font-family: 'Segoe UI', Arial, sans-serif; color: #2b3648; font-size: 11.5px; line-height: 1.55; margin: 0; }
  .cover { height: 92vh; display: flex; flex-direction: column; justify-content: center; align-items: center; text-align: center; page-break-after: always; }
  .cover .kicker { color: #E8A33D; font-weight: 700; letter-spacing: .18em; font-size: 13px; }
  .cover h1 { font-size: 40px; color: #1F3A5F; margin: 18px 0 10px; }
  .cover p { max-width: 520px; color: #6b7688; font-size: 14px; }
  .cover .foot { margin-top: 48px; color: #8a94a6; font-size: 11px; }
  h1 { color: #1F3A5F; font-size: 22px; border-bottom: 2px solid #E8A33D; padding-bottom: 6px; }
  h2 { color: #1F3A5F; font-size: 16px; margin-top: 26px; page-break-after: avoid; }
  h3 { color: #2C6E9B; font-size: 13px; margin-top: 20px; page-break-after: avoid; }
  img { max-width: 100%; border: 1px solid #e2e6ea; border-radius: 4px; page-break-inside: avoid; }
  p[align="center"] { text-align: center; }
  em { color: #6b7688; }
  blockquote { border-left: 3px solid #E8A33D; margin: 12px 0; padding: 6px 14px; background: #faf7f0; color: #4a5568; }
  table { border-collapse: collapse; width: 100%; margin: 10px 0; page-break-inside: avoid; }
  th, td { border: 1px solid #e2e6ea; padding: 6px 9px; text-align: left; }
  th { background: #f3f6fb; color: #1F3A5F; }
  code { background: #f3f6fb; padding: 1px 5px; border-radius: 3px; font-size: 10.5px; }
`;

(async () => {
  const { pathToFileURL } = require('url');
  const browser = await chromium.launch();
  const page = await browser.newPage();
  for (const job of JOBS) {
    const md = fs.readFileSync(path.join(DOCS, job.src), 'utf8');
    const body = marked.parse(md);
    const html = `<!doctype html><html><head><meta charset="utf-8"><style>${CSS}</style></head><body>
      <div class="cover"><div class="kicker">${job.cover[0]}</div><h1>${job.cover[1]}</h1><p>${job.cover[2]}</p>
      <div class="foot">Lighthouse Nonprofit Technologies · CaseLight · AGPL-3.0 — screens show synthetic demo data only</div></div>
      ${body}</body></html>`;
    // Render from a real file inside docs/ so relative screenshot paths resolve —
    // a setContent page (about:blank origin) cannot load file:// subresources.
    const tmp = path.join(DOCS, `.build-${path.basename(job.src, '.md')}.html`);
    fs.writeFileSync(tmp, html);
    await page.goto(pathToFileURL(tmp).href, { waitUntil: 'networkidle' });
    fs.unlinkSync(tmp);
    await page.pdf({
      path: path.join(DOCS, job.out),
      format: 'Letter',
      margin: { top: '18mm', bottom: '16mm', left: '14mm', right: '14mm' },
      displayHeaderFooter: true,
      headerTemplate: '<span></span>',
      footerTemplate: `<div style="width:100%;font-size:8px;color:#8a94a6;padding:0 14mm;display:flex;justify-content:space-between;"><span>${job.title}</span><span>Page <span class="pageNumber"></span> of <span class="totalPages"></span></span></div>`,
      printBackground: true,
    });
    console.log('built', job.out);
  }
  await browser.close();
})();
