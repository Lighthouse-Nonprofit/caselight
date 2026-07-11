// FRAMEWORK
// POAM-017b: `jquery3` is jquery-rails' 3.7.1 asset (the bare `jquery` name is the gem's
// EOL 1.12.4 legacy copy — 4 CVEs fixed only in 3.5+). jquery-migrate 3.5.2 (vendored)
// rides along TEMPORARILY: it restores removed 1.x APIs for the aging vendored plugins
// and console.warns every deprecated call ("JQMIGRATE:"). Remove it (R13) once the
// smoke set logs no warnings. NB dataTables below now resolves to the vendored 1.13.11
// (vendor/assets shadows the jquery-datatables-rails gem's 1.10.10, which predates
// official jQuery-3 support).
//= require jquery3
// UNIT 12: rails-ujs (bundled in actionview 7.2) replaced the legacy jquery_ujs (jquery-rails).
// Same data-method/data-confirm/data-remote CSRF layer + auto-start, but jQuery-free and the
// supported path on Rails 7. Drop-in: no ajax:* handlers and no $.rails API use in this app.
// (jquery-rails still provides the `jquery` asset above; only its UJS shim is retired.)
//= require rails-ujs
//= require jquery-ui
//= require bootstrap-sprockets
//= require jquery.steps.min
//= require jquery.validate
//= require jquery.validate.additional-methods
//= require jquery.nicescroll.min
//= require dataTables/jquery.dataTables
// POAM-017c: Tom Select 2.x (vendored) replaced the hand-vendored select2 3.5.2.
// All call sites go through the CIF.Select adapter (shared/select_widget, in the
// LOAD MODULE block below — it needs the CIF namespace).
//= require tom-select
//= require cocoon
//= require image_upload_previewer/image_upload_previewer
//= require image_upload
//= require bootstrap-datepicker/core
//= require bootstrap-datepicker/locales/bootstrap-datepicker.en-GB.js
//= require cocoon
//= require datepicker
//= require metisMenu/jquery.metisMenu.js
//= require chart.umd
//= require dropzone
//= require form-builder.min.js
//= require form-render.min.js
//= require jquery.extendext
//= require doT
//= require query-builder
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
//= require bootstrap_file_input/purify.min.js
//= require bootstrap_file_input/fileinput.js
//= require bootstrap_file_input/fa/theme.min.js
//= require bootstrap_file_input/explorer/theme.min.js

// WRAPBOOTSTRAP
//= require iCheck/icheck.min.js
//= require wrapbootstrap/inspinia.js
//= require slimscroll/jquery.slimscroll.min.js
//= require toastr/toastr.min.js

//LOAD MODULE
//= require namespace
//= require shared/select_widget
//= require shared/rule_builder
//= require util
//= require initializer
//= require common
//= require jquery.infinitescroll.min
//= require footable.all.min

//APPLICATION JS
//= require check_duplicate_array.js
//= require custom_form_builder
//= require table_scroll
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
//= require families/index
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
