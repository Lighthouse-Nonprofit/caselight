# POAM-017g verification — Bootstrap 3.4.1 + INSPINIA → Bootstrap 5.3.8 (in-house theme)

Closure evidence for POAM-017g (see `vulnerability-poam.md`). The migration retired the
EOL Bootstrap 3.4.1 line, the INSPINIA 2.6.2 commercial theme (which was vendored WITHOUT
a license in this public AGPL repository — an inherited compliance defect resolved by
deletion), and the BS3-era plugin ring (iCheck, slimscroll, animate.css,
bootstrap-datepicker, krajee fileinput 4.4.1, glyphicon fonts).

## Program shape and SHAs

| Stage | PRs | Main SHA after | Content |
|---|---|---|---|
| Prep P1–P6 | #140–#145 | `b2a9161` (frozen BS3 baseline) | badge chokepoint + Brakeman retirement; inert simple_form BS5 wrappers; PDF print stack self-hosted; dead-INSPINIA prune + glyphicon→FA swap; BS5 assets vendored unwired (`vendor/assets/BS5-VENDOR-PROVENANCE.md`, sha256 per tarball); Playwright gates + BS3 baseline capture |
| Handoff | #146 | `80ee9d9` | flip spec + companion gates committed (`qa/playwright/BS5-FLIP-PLAN.md`) |
| THE FLIP (F1–F10) | #147 | `ffbfba2` | gems dropped; `caselight_theme/` (BS 5.3.8 core + navy/amber restyle on the existing `.ibox`/shell markup); simple_form flip; codemods (`qa/codemods/bs5_flip.rb`); hand-work; JS conversions (`caselight_shell.js`, vanillajs-datepicker adapter); deletions (−13,436 net lines); `bootstrap3_removal_guard_spec` + `layout_shell_bs5_spec` |
| Q1 visual QA | #148 | `4d6743c` | 30-surface screenshot review: 13 findings fixed (2 functional: jquery.steps clip, tab-pane deactivation); `bs5_pixeldiff.js` gate added; zero app-side sass deprecations; BS5 reference baseline captured |
| Q2 compat retirement | #149 | `2a96382` | sr-only→visually-hidden (+ a11y specs); button.close→.btn-close ×29; guard bans extended; pixeldiff proved visual transparency (0.00–0.02 % on all 30 surfaces) |
| Q3 feature suite | #150 | (merge SHA in git log) | cuprite js driver (first feature-suite run since PhantomJS); **5 real app bugs found + fixed**, incl. two live workflow blockers (assessment submission, program-stream draft saves); suite 470/0/8 |

## Gates (all blocking, all green at close)

- CI suite (js-excluding, in-container): **1523 examples / 0 failures / 8 pending**
- js feature suite (cuprite/Chromium, in-container): **470 / 0 / 8** — first green run since the PhantomJS retirement
- `qa/playwright/bs5_sweep.js`: 30 surfaces, 0 assertion failures, 0 non-allowlisted console errors; `compare.html` contact sheet signed pair-by-pair at the flip
- `qa/playwright/bs5_interactions.js`: **14/14** silent-failure blocks (incl. the Q1-hardened old-pane-deactivation assert)
- `qa/playwright/bs5_pixeldiff.js`: 0 FAIL per polish rung against the BS5 reference baseline
- `git diff --stat main -- db/` across the flip: **empty** (pure-revert insurance; rollback = revert of the merge commit)
- Brakeman: flip-neutral; CSP: `csp_violation` count **0** across all sweep windows
- `spec/lib/bootstrap3_removal_guard_spec.rb`: Gemfile/lock bans, dartsass path ban, deleted-tree globs, view-vocabulary bans (col-xs, glyphicon, panel-\*, btn-default, i-checks, pull-\*, `label label-`, sr-only, button.close, bootstrap-valued data-toggle), JS API bans, compiled-CSS discriminator (`--bs-` present, glyphicon font absent)

## Evidence locations

- Screenshots + interaction logs (outside the repo): dev-host `~/caselight-evidence/poam-017g/`
  — `baseline-b2a9161/` (BS3, frozen pre-flip), `candidate-flipwip/` + `compare.html`
  (flip gate), `candidate-q1wip/` `candidate-q1v2/` `candidate-q2/` (polish rungs),
  `baseline-bs5-4d6743c/` (the BS5 reference baseline; `BASELINE_SHA.txt` is the index)
- Vendored-asset provenance: `vendor/assets/BS5-VENDOR-PROVENANCE.md` (sha256 per upstream tarball)
- Gate usage: `qa/playwright/README.md`

## Deliberate survivors (documented, not drift)

- `.ibox` classnames (537 occ/142 files) restyled as the CaseLight card component
- Font Awesome **4.7** (icon font only; future FA6 ledger item)
- `.dropdown-menu li > a` compat styling (dropdown items are partly decorator-emitted;
  treated as the permanent supported pattern, like the `.btn-xs` utility)
- `.has-error` (JS-driven validation state, compat-styled)
- The PDF print layout stays permanently on inlined Bootstrap 3.3.6 (wkhtmltopdf's
  QtWebKit cannot render BS5 flexbox; the layout is self-contained + network-free)
- jquery.steps (restyled; replacement is a future ledger item)
