// POAM-017a — app-wide Trix configuration (replaces the EOL TinyMCE 4).
//
// Attachments are DELIBERATELY disabled: the render-side sanitizer
// (RichTextHelper::RICH_TEXT_TAGS) denies <img> as a tracking-pixel/exfil vector
// on PII-adjacent content, and file uploads already have their own authorized
// path (Dropzone -> attachments controller). Cancelling trix-file-accept blocks
// drag-drop and paste attachments before Trix creates one; the toolbar's file
// button group is hidden in rich_text.scss.
//
// No init call is needed per editor: <trix-editor input="..."> binds itself and
// keeps the hidden input's value synced on every change, so the progress-note
// form's custom Dropzone submit interception reads a current value without any
// sync-before-submit hook.
document.addEventListener('trix-file-accept', function (event) {
  event.preventDefault();
});
