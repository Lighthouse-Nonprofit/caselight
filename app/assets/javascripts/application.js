// FRAMEWORK
// R12D: jQuery 4.0.0, vendored (the jquery-rails gem ships no jquery4 asset and left the
// bundle with it). The transitional jquery-migrate 4.0.2 bridge was REMOVED (post-CSP-soak
// cleanup) after a full-surface JQMIGRATE sweep: the shipped 4.0 core still defines the
// event shorthands and .bind/.hover (deprecated, working), and the only genuinely-removed
// APIs with live callers (isFunction/proxy/trim/camelCase — all in vendored plugins) are
// restored explicitly by jquery4_compat below (census + growth-ban in its guard spec).
// jQuery UI 1.14 below is 4.0-compatible (>= 1.13.3 required).
//= require jquery4.min
//= require jquery4_compat
// UNIT 12: rails-ujs (bundled in actionview 7.2) replaced the legacy jquery_ujs (jquery-rails).
// Same data-method/data-confirm/data-remote CSRF layer + auto-start, but jQuery-free and the
// supported path on Rails 7. Drop-in: no ajax:* handlers and no $.rails API use in this app.
// (jquery-rails still provides the `jquery` asset above; only its UJS shim is retired.)
//= require rails-ujs
// POAM-017g flip: Bootstrap 5.3 JS bundle (vendored, Popper included). Replaces
// bootstrap-sprockets (BS3). Loaded right after rails-ujs so the components (modal, dropdown,
// collapse, tab, tooltip, popover) are on window.bootstrap before the app modules below.
//= require bootstrap.bundle.min
//= require jquery-ui
//= require jquery.steps.min
//= require jquery.validate
//= require jquery.validate.additional-methods
// (D2: jquery.nicescroll + dataTables/* requires removed — the feature-disabled cosmetic
// table inits were replaced by the native .cl-table-scroll pattern; see shared/record_table.)
// POAM-017c: Tom Select 2.x (vendored) replaced the hand-vendored select2 3.5.2.
// All call sites go through the CIF.Select adapter (shared/select_widget, in the
// LOAD MODULE block below — it needs the CIF namespace).
//= require tom-select
//= require cocoon
//= require image_upload_previewer/image_upload_previewer
//= require image_upload
// POAM-017g flip: vanillajs-datepicker (jQuery-free) replaced bootstrap-datepicker. en-GB
// only sets month/day names; the app pins ISO yyyy-mm-dd format at every site via the
// shared/date_picker.js adapter (required in the LOAD MODULE block below).
//= require vanillajs-datepicker/datepicker-full.min
//= require vanillajs-datepicker/en-GB
//= require cocoon
//= require metisMenu/jquery.metisMenu.js
//= require chart.umd
//= require dropzone
// formBuilder 3.23.1 (kevinchappell/formBuilder, MIT), vendored from the npm 3.23.1 dist
// (R12B, POAM-017f). Upgraded from the 2016-vintage 1.24.2. NOTES: (1) 3.x ships NO dist
// CSS -- styles + a base64-woff icon font are injected at runtime, which consumes the
// style-src 'unsafe-inline' + font-src data: the policy already keeps for FullCalendar 6;
// (2) en-US strings are compiled in -- no runtime .lang fetch (verified; do not pass
// i18n.locale without vendoring lang files first); (3) eval gate: zero eval(/new Function;
// the single Function( occurrence is lodash's unreachable global-this fallback, identical
// to the one in our standalone vendored lodash below; (4) requires jQuery + jQuery UI
// sortable, both loaded above.
//= require form-builder.min.js
//= require stickyfill.js
//= require lodash/lodash.min.js

// POAM-017a: Trix 2 (vendored) replaced the EOL TinyMCE 4. rich_text holds the app-wide
// Trix config (attachments disabled — the render sanitizer denies <img>; Dropzone is the
// only upload path).
//= require trix
//= require rich_text
// POAM-017d: FullCalendar 6 standard bundle (vendored; jQuery/moment-free — the moment
// require died with the fullcalendar-rails/momentjs-rails gems). FC6 injects its CSS via a
// runtime <style> element, so the CSP enforce flip (POAM-017f) must keep
// style-src 'unsafe-inline' unless a style-nonce pass is added.
//= require fullcalendar
// POAM-017g flip: krajee bootstrap-fileinput 5.5.4 (BS5) replaced 4.4.1. purify (DOMPurify)
// is the optional preview-HTML sanitizer fileinput uses; kept, moved to the vendor JS root.
//= require purify.min
//= require bootstrap_file_input5/fileinput.js
//= require bootstrap_file_input5/themes/fa4-theme.js
//= require bootstrap_file_input5/themes/explorer-fa4-theme.js
// Q1: compact defaults (fileinput 5 grew a dropzone/Remove/close vs the 4.4.1 baseline).
//= require shared/file_input_defaults

// SHELL + TOASTS
// POAM-017g flip: caselight_shell.js replaced wrapbootstrap/inspinia.js (live shell behaviours
// only). iCheck (native form-check now) and slimscroll (native overflow-y) are gone.
//= require caselight_shell
//= require toastr/toastr.min.js

//LOAD MODULE
//= require namespace
//= require shared/select_widget
//= require shared/rule_builder
//= require shared/auto_submit
// POAM-017g flip: vanillajs-datepicker adapter (global init + the rule-builder embed).
// Replaces the old top-level `datepicker` require (bootstrap-datepicker global init).
//= require shared/date_picker
//= require util
//= require initializer
//= require common
//= require footable.all.min

//APPLICATION JS
//= require check_duplicate_array.js
//= require custom_form_builder
//= require shared/record_table
//= require filters
//= require assessments/form
//= require tasks/form
//= require tasks/index
//= require calendars/index
//= require dashboards/index
//= require case_notes/form
//= require cases/form
//= require admin/tasks
//= require clients/index
//= require report_creator
//= require clients/show
//= require clients/form
//= require families/form
//= require families/show
//= require users/show
//= require users/index
//= require users/form
//= require partners/index
//= require partners/form
//= require stages/form
//= require able_screening_questions/form
//= require able_screening_answers/form
//= require data_trackers/index
//= require progress_notes/form
//= require progress_notes/index
//= require changelogs/index
//= require domains/form
//= require custom_fields/form
//= require custom_fields/index
//= require custom_fields/show
//= require custom_fields/shared_fields
//= require shared/version_per_page_form
//= require notifications/index
//= require sessions/new
//= require sessions/new_passkey
//= require passkeys/show
//= require case/quarterly_reports/index
//= require client_advanced_searches/index
//= require program_streams/form
//= require custom_field_properties/form
//= require program_streams/index
//= require program_streams/show
//= require client_enrollments/form
//= require leave_programs/form
//= require client_enrollment_trackings/form
//= require organizations/index
//= require prevent_required_file_uploader
