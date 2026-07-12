# POAM-017g — THE FLIP PR spec (F1–F10) + gates

The executable spec for the Bootstrap 3.4.1 + INSPINIA → Bootstrap 5.3 cutover. Prep rungs
P1–P6 are MERGED (PRs #140–#145); the frozen BS3 baseline SHA is **b2a9161** (screenshots +
logs in WSL `~/caselight-evidence/poam-017g/baseline-b2a9161/`). User-ratified decisions:
in-house theme on stock BS 5.3 (INSPINIA deleted — unlicensed commercial theme in an AGPL
repo), FA 4.7 stays, ONE flip PR then polish rungs. Companion docs here:
`BS5-FLIP-AUDITS.md` (option hashes + cascade inventory), `README.md` (gate usage).

Already in place for you: BS5 assets vendored UNWIRED (`vendor/assets/**`, see
`vendor/assets/BS5-VENDOR-PROVENANCE.md` — bootstrap 5.3.8 scss+bundle, vanillajs-datepicker
1.3.4+en-GB+bs5 css, fileinput 5.5.4+fa4/explorer-fa4, datatables-bs5 1.13.11,
tom-select.bootstrap5.css 2.6.2); inert `:bs5_*` simple_form wrappers
(`config/initializers/simple_form_bootstrap.rb`, spec-locked); `cl_badge` chokepoint
(`application_helper.rb` — the label→badge flip is ONE method + its spec); PDF layout
self-contained and EXEMPT from all codemods (`layouts/pdf_design.html.haml` +
`government_reports/*.pdf.haml` — permanently BS 3.3.6).

## Ordered internal checklist (each block must compile/boot before the next)

- **F1 wiring:** Gemfile −`bootstrap-sass` −`bootstrap-datepicker-rails` (+lock);
  `config/initializers/dartsass.rb` drop the bootstrap-sass gem load-path (keep
  vendor/assets path + --quiet-deps); `application.js`: −bootstrap-sprockets
  −`bs3_jquery4_data_shim` (temporary shim DIES here) +`bootstrap.bundle.min` (right after
  rails-ujs), datepicker/fileinput/iCheck/inspinia/slimscroll require swaps, +datatables-bs5.
- **F2 theme:** new `app/assets/stylesheets/caselight_theme/` — `_variables` (navy/amber
  palette from `wrapbootstrap/base/_refresh.scss` → BS5 vars; **`$font-size-base: .8125rem`**
  is the whole-app drift lever; Open Sans), `_root`, `_shell`, `_sidebar` (metisMenu port;
  native overflow-y replaces slimscroll), `_topnav`, `_ibox` (**KEEP the .ibox classnames**,
  restyle on card DNA — 537 occ/142 files stay untouched), `_tables`, `_login`, `_badges`,
  `_compat` (`.sr-only` alias of visually-hidden + our permanent `.btn-xs` utility),
  `_focus-ring` (port from `_refresh`), `_print`. `application.scss`: wrapbootstrap import →
  `caselight_theme/theme`; iCheck/animate/tom_select_bs3/datepicker css swaps;
  **`_refresh_polish` import stays literally LAST** (rewrite its rules for renamed classes).
- **F3 simple_form:** point `default_wrapper`/`wrapper_mappings` at the `:bs5_*` set;
  `button_class: 'btn btn-primary'`; update `spec/helpers/simple_form_bs5_wrappers_spec.rb`
  (the inertness example flips to a default-is-BS5 assertion).
- **F4 codemods** (committed scripts under `qa/codemods/`, handle BOTH haml attr styles
  — `"data-toggle" => "x"` AND `data: { toggle: 'x' }` — AND JS option-hash strings;
  EXCLUDE `pdf_design.html.haml` + `*.pdf.haml`), in order: col-xs→col (+offset);
  pull→float-start/end, img-responsive→img-fluid, hidden→d-none (incl. `hidden_class`
  helper); panel→card (+17 scss selector sites); `btn btn-outline btn-danger`→
  `btn-outline-danger` THEN btn-default→btn-outline-secondary; `label label-*`→
  `badge text-bg-*` (flip cl_badge + status_style + program_stream_decorator + the
  cl_badge_spec expectations in the same commit); caret line deletion; forms
  (input-group-addon→input-group-text, help-block→form-text, control-label→form-label/
  col-form-label hand-checked, hand-written form-group→mb-3); data-toggle/target/dismiss/
  parent/placement→data-bs-* **value-scoped to bootstrap values only** (footable's
  `data-toggle="true"` in notification views must survive); iCheck removal (i-checks→
  form-check-input ×23 files, .checkbox/.radio→.form-check rewrap, init deletions in
  common.js + 3 sites, vendored iCheck files deleted).
- **F5 hand-work:** 18 dropdowns (+.dropdown-item/.dropdown-divider), 25 modals
  (`button.close`→`.btn-close`, no × text), 2 nav-tabs (+.nav-item/.nav-link, active moves
  to the link), has-error→is-invalid wiring (`error_message` helper →
  `invalid-feedback d-block`; `shared/fields/*` + `program_streams/fields/*` rewritten
  **with their a11y specs in the same commit**; jquery.validate errorClass config),
  layouts (`_side_menu` [keep metisMenu markup; count badges → `badge text-bg-light
  float-end`], `_top_navbar` [`navbar-right pull-right`→`ms-auto`, `visible-xs-block`→
  `d-block d-sm-none`], errors ×3), well ×4/thumbnail ×2/list-group audit.
- **F6 JS:** 5 `.modal(`→`bootstrap.Modal.getOrCreateInstance` (case_notes/form.js:100,
  calendars/index.js:121,192, clients/form.js:82, assessments/form.js:207); 2 `.tab(`→
  `bootstrap.Tab` (program_streams/index.js:30, custom_fields/index.js:10); popover
  (calendars/index.js:55); new `caselight_shell.js` replacing `wrapbootstrap/inspinia.js`
  (LIVE parts only: metisMenu init, ibox collapse/close/fullscreen, minimalize, body-small,
  popover/tooltip init; DROP slimscroll/demo chrome/localStorage prefs/WinMove).
- **F7 plugins:** datepicker adapter `shared/date_picker.js` — **format is ISO
  `yyyy-mm-dd` EVERYWHERE** (see AUDITS; the interaction gate pins it); autoclose→autohide,
  setDate/destroy instance API, `.input-group.date` component-mode (adapter binds the inner
  input + wires the addon), en-GB registered, `rule_builder.js:428` embed accepts the same
  hash. fileinput: theme `'explorer'`→`'explorer-fa4'` + per-site option re-verify (7 sites,
  AUDITS). DataTables bs5 css/js wired, sites unchanged. jquery.steps KEPT — restyle
  `step.css` only. tom-select bs5 theme replaces the `tom_select_bs3.scss` shim.
- **F8 specs:** 6 feature files (.panel→.card ×2, label→`badge text-bg-*` ×1,
  `.form-group.has-error`→`.is-invalid`+`.invalid-feedback` ×3); **run the FULL feature
  suite locally once**, record counts in the PR.
- **F9 deletions:** entire `wrapbootstrap/` scss+js trees, `bs3_jquery4_data_shim.js`,
  iCheck, slimscroll, animate, bootstrap-datepicker css, fileinput 4.4.1 tree,
  `tom_select_bs3.scss`, `public/fonts/bootstrap/` (glyphicon fonts + `$icon-font-path`).
- **F10 guards:** new `spec/lib/bootstrap3_removal_guard_spec.rb` (mirror
  highcharts/query_builder structure): Gemfile/lock bans; dartsass.rb gem-path ban +
  vendored-BS5 assertion; deleted-tree globs; view bans (col-xs-, glyphicon,
  panel-heading/body, btn-default, input-group-addon, help-block, i-checks,
  bootstrap-valued data-toggle, pull-*, `label label-`) with pdf exemptions; JS bans
  (bootstrap-sprockets, .icheck(, .modal(, .tab( — comment-stripped, shell/adapters
  allowlisted); compiled-css gate (`--bs-` present [zero today = perfect discriminator],
  `Glyphicons Halflings`/`.md-skin` absent, `.ibox` present-as-theme). Plus
  `spec/requests/layout_shell_bs5_spec.rb` (3 anchors: shell themed + data-bs-toggle
  present; no bootstrap-valued data-toggle; flash renders `.alert-dismissible .btn-close`).

## THE FLIP GATE (all blocking)

CI green (suite ~1494 shape + new guards) · brakeman clean · `git diff --stat main -- db/`
EMPTY (pure-revert insurance) · `bs5_sweep.js --out <evidence>/candidate-<sha> --compare
<evidence>/baseline-b2a9161` → 0 assertion failures, 0 non-allowlisted console errors,
`compare.html` checklist signed pair-by-pair (deliberate-restyle review, NOT pixel-diff) ·
`bs5_interactions.js` **14/14** · `soak_coverage.js` + `qa_rungA.js` green · app-log grep
`csp_violation` = **0** since sweep start · full feature suite run locally, counts recorded.

## After the flip: polish rungs Q1–Q4

Q1 per-surface visual QA + `_refresh` merge-down audit + re-baseline (BS5 reference) +
pixelmatch tooling for polish PRs · Q2 sr-only→visually-hidden rename (views + the 2
pinning a11y specs + drop the alias, one PR) · Q3 full local feature sweep · Q4 POAM-017g →
Closed + `docs/compliance/poam-017g-verification.md` + README/SSP/CLAUDE.md stack rows +
ledger FA6/jquery.steps-replacement/datagrid-2.x as separate items. Box deploys ONCE after
Q4 (`bootstrap.sh` rerun; ENFORCE_CSP untouched). Rollback = `git revert` of the flip merge
(no migrations).
