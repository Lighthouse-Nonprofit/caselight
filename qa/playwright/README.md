# qa/playwright — the POAM-017g Bootstrap-5 migration gates

Two Playwright scripts form the empirical gate for the BS3 → BS5 flip (the CI suite excludes
feature specs and is nearly blind to class renames — these are the real correctness check):

- **`bs5_sweep.js`** — visual + console gate. Sweeps ~30 authenticated surfaces, full-page
  screenshot each (1440×900), framework-agnostic DOM assertions (BS3/BS5 selector unions:
  shell visible, themed body, `.ibox,.card` containers, no horizontal overflow, Open Sans
  face loaded, form controls on form pages), console/page errors vs a known-noise allowlist.
  With `--compare <baselineDir>` it emits `compare.html`, a side-by-side contact sheet with
  the human checklist.
- **`bs5_interactions.js`** — the SILENT-failure gate. The `data-bs-*` rename and the
  bootstrap-sprockets → vanilla swap break interactive components with no console error;
  this exercises one representative of every class: declarative + JS modals, dropdowns,
  collapse, tabs, popover, datepicker (format pinned `yyyy-mm-dd` — the app's configured
  shape at every site), krajee fileinput, DataTables init, jquery.steps chrome, checkbox
  visibility+toggle (iCheck today / form-check post-flip), Tom Select, toastr opacity (the
  BS5 `.toast` collision check), and a real save → flash round-trip.

## Running (from the Windows Playwright rig)

```powershell
$env:NODE_PATH="$env:LOCALAPPDATA\npm-cache\_npx\<hash>\node_modules"   # playwright install
node qa/playwright/bs5_sweep.js --out <evidence>/baseline-<sha>
node qa/playwright/bs5_sweep.js --out <evidence>/candidate-<sha> --compare <evidence>/baseline-<sha>
node qa/playwright/bs5_interactions.js
```

Evidence lives OUTSIDE the repo (WSL `~/caselight-evidence/poam-017g/`); outcomes are
recorded in `docs/compliance/poam-017g-verification.md` at program close. Login uses the
SEEDED DEV demo admin (synthetic data; override via QA_BASE/QA_EMAIL/QA_PASSWORD).

Both scripts exit non-zero on any failure. Run them green on the BS3 baseline BEFORE the
flip branch cuts (P6), and as blocking gates on the flip PR and every polish rung.

## bs5_pixeldiff.js — polish-rung drift gate (Q1+)

Once both runs are on the SAME framework (post-flip), `bs5_pixeldiff.js` compares two sweep
evidence dirs pixel-by-pixel (pixelmatch): a polish PR may move the surfaces it deliberately
touches (`--allow a,b,c`); any OTHER surface drifting past `--threshold` (default 1%) or
reflowing more than 2% in height fails the gate, and a diff PNG is written for review.

```powershell
cd qa/playwright; npm install   # pixelmatch + pngjs (package.json; node_modules git-ignored)
node qa/playwright/bs5_pixeldiff.js --baseline <evidence>/baseline-<sha> `
  --candidate <evidence>/candidate-<sha> --allow login,tasks
```

(A BS3-vs-BS5 compare flags all 30 surfaces by design — pixeldiff only means something
against a BS5 baseline.)

## What the shakedown already caught (why this gate earns its keep)

Running these against the BS3 baseline surfaced three REAL latent regressions from the
jQuery 4 bump — all silent, none covered by the CI suite:
1. Bootstrap 3.4.1 collapse dead on first click app-wide (null-prototype bulk `.data()`
   vs `/show|hide/.test`) — index search-filter panels included;
2. tooltips/popovers dead app-wide (same root cause vs the 3.4 sanitizer's
   `hasOwnProperty`) — fixed at the root by `app/assets/javascripts/bs3_jquery4_data_shim.js`
   (TEMPORARY, deleted at the flip with bootstrap-sprockets);
3. a `val()` TypeError on /admin/users/new at init (`users/form.js` bare `$(this)`).
