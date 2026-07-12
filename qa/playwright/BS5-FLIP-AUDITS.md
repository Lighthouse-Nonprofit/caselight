# POAM-017g flip audits (P6) — option hashes + cascade selectors the flip must honor

Extracted 2026-07-12 from the live tree. The flip PR's plugin swaps and codemods are held
to these facts.

## Datepicker sites (bootstrap-datepicker → vanillajs-datepicker)

**FORMAT IS ISO `yyyy-mm-dd` at every site** (not locale dd/mm/yyyy — the en-GB locale
file only affects month/day names). The interaction gate pins this.

| site | options | notes |
|---|---|---|
| `datepicker.js:5` (global init) | `autoclose, format: 'yyyy-mm-dd', todayHighlight, disableTouchKeyboard` | `autoclose→autohide`; `disableTouchKeyboard` has no vanillajs equivalent (drop, note) |
| `datepicker.js:15-21` | same + `.datepicker('setDate', new Date())` | instance API: `.setDate(date)` |
| `datepicker.js:23` | `.datepicker('remove')` on disabled inputs, **`.input-group.date` component mode** | vanillajs binds the INPUT, not the group — the adapter resolves the inner input + wires the addon click; `remove→destroy()` |
| `case_notes/form.js:134-139` | `autoclose, format, todayHighlight` + `.datepicker('setDate', null)` | `setDate(null)` → `setDate({clear: true})` or `.destroy()+re-init` — verify |
| `shared/rule_builder.js:428` | `$(input).datepicker(descriptor.plugin_config \|\| {})` | the rule-builder embed — descriptor config comes from FilterTypes; adapter must accept the same hash |

(8 total call sites; the rest repeat the global-init shape.)

## fileinput sites (krajee 4.4.1 → 5.5.4)

All sites use `theme: 'explorer'` → **5.x theme name is `explorer-fa4`** (vendored). The
option hashes embed BS3 button classes (`removeClass: 'btn btn-danger btn-outline'`) —
**the flip codemods must include JS option-hash strings**, not just haml.

| site | options |
|---|---|
| `program_streams/show.js:34` | `showUpload:false, removeClass:'btn btn-danger btn-outline', browseLabel, theme:'explorer'` |
| `client_enrollments/form.js:19` | same + `allowedFileExtensions:[jpg,png,jpeg,doc,docx,xls,xlsx,pdf]` |
| + 5 more sites (case_notes, client_enrollment_trackings, leave_programs, custom_field_properties, assessments) | same family — re-verify each against the 5.x changelog (`showRemove`/`layoutTemplates` renames are the usual suspects) |

## Cascade layers (re-audit at flip)

- `wrapbootstrap/base/_refresh.scss` — dies with the INSPINIA tree; port the
  `:focus-visible` ring system + any CaseLight-design rules into `caselight_theme/*`.
- `_refresh_polish.scss` — REWRITTEN in the flip (targets `.ibox`, show-page tables,
  household chips); its import stays literally last in application.scss (contract).
- `changelogs/index.scss` `.glyphicon-pencil/-trash` selectors — years-dead orphans (views
  use fa_icon); delete at flip, do NOT reactivate.

## Temporary shims that DIE at the flip (deletion list additions)

- `app/assets/javascripts/bs3_jquery4_data_shim.js` (+ its application.js require) —
  BS3-internals-only normalization of jQuery 4's null-prototype bulk `.data()`.
