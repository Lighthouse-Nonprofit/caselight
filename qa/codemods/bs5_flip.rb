# frozen_string_literal: true
#
# qa/codemods/bs5_flip.rb — POAM-017g THE FLIP mechanical codemod.
#
# Rewrites the Bootstrap-3 / INSPINIA class + data-attribute vocabulary in the HAML views,
# the per-view SCSS selectors, and JS class-string / option-hash literals to Bootstrap 5.
# Committed for reproducibility (the F10 guard spec bans the BS3 tokens this removes).
#
# SCOPE / EXCLUSIONS (hard rules from BS5-FLIP-PLAN.md):
#   * app/views/**/*.haml, EXCEPT *.pdf.haml and layouts/pdf_design.html.haml (permanently BS3.3.6)
#   * app/assets/stylesheets/**/*.scss, EXCEPT caselight_theme/ (the new theme), wrapbootstrap/
#     (deleted at F9) and government_reports/ (PDF-exempt)
#   * app/assets/javascripts/**/*.js, EXCEPT vendored (only app-authored files)
#
# Idempotent: re-running makes no further changes (every rule maps a BS3 token to a BS5 token
# that the same rule no longer matches). Run:  ruby qa/codemods/bs5_flip.rb
#
# NOT handled here (deliberately left to F5 hand-work, because they are context-dependent):
#   modal button.close -> .btn-close, nav-tabs .nav-item/.nav-link + data-bs-toggle=tab,
#   dropdown .dropdown-item/.dropdown-divider, has-error -> is-invalid error wiring, the iCheck
#   JS command calls (.iCheck('check')), the .checkbox column-picker wrapper, and layout chrome
#   (navbar-right -> ms-auto). .well/.thumbnail/.label-lg keep their markup (styled via _compat).

require 'find'

ROOT = File.expand_path('../..', __dir__)

def haml_files
  base = File.join(ROOT, 'app/views')
  Find.find(base).select do |p|
    p.end_with?('.haml') &&
      !p.end_with?('.pdf.haml') &&
      !p.end_with?(File.join('layouts', 'pdf_design.html.haml'))
  end
end

def scss_files
  base = File.join(ROOT, 'app/assets/stylesheets')
  Find.find(base).select do |p|
    next false unless p.end_with?('.scss')
    rel = p.sub(base + '/', '')
    !rel.start_with?('caselight_theme/') &&
      !rel.start_with?('wrapbootstrap/') &&
      !rel.start_with?('government_reports/')
  end
end

def js_files
  base = File.join(ROOT, 'app/assets/javascripts')
  Find.find(base).select { |p| p.end_with?('.js') }
end

# ---- class-token transforms applied to HAML + SCSS + JS ------------------------------------
# Each entry is [regexp, replacement]. Order matters (offsets before cols, panel-parts before
# bare panel, label colors before base label, etc.).
CLASS_RULES = [
  # grid: offsets first, then columns
  [/\bcol-xs-offset-(\d+)\b/, 'offset-\1'],
  [/\bcol-(sm|md|lg|xl)-offset-(\d+)\b/, 'offset-\1-\2'],
  [/\bcol-xs-(\d+)\b/, 'col-\1'],

  # floats / images
  [/\bpull-right\b/, 'float-end'],
  [/\bpull-left\b/, 'float-start'],
  [/\bimg-responsive\b/, 'img-fluid'],

  # panel -> card (heading/body/footer/title first; then drop color/group modifiers; then bare)
  [/\bpanel-heading\b/, 'card-header'],
  [/\bpanel-body\b/, 'card-body'],
  [/\bpanel-footer\b/, 'card-footer'],
  [/\bpanel-title\b/, 'card-title'],
  [/\.panel-(default|primary|success|info|warning|danger|group)\b/, ''],  # dot-notation modifier
  [/\bpanel-(default|primary|success|info|warning|danger|group)\b/, ''],  # string-form modifier
  [/\bpanel(?!-)\b/, 'card'],  # bare panel (skips panel-pusher etc.)

  # labels -> badges. Colors first (dot + string), then interpolation, then base class.
  [/\blabel-warning-light\b/, 'text-bg-warning'],
  [/\blabel-(info|primary|success|danger|warning)\b/, 'text-bg-\1'],
  [/\blabel-default\b/, 'text-bg-light'],
  [/(["'])label label-/, '\1badge text-bg-'],   # string form: "label label-#{x}" / 'label label-success'
  [/\blabel-#\{/, 'text-bg-#{'],                 # any remaining interpolation
  # dot-notation base class -> .badge. Restricted to `.label` immediately FOLLOWED BY the
  # badge colour class (`.text-bg-*`, produced by the colour rename above) or a `.label-*`
  # modifier (`.label-margin`/`.label-lg`). Real HAML badges are always this chained shape;
  # this excludes Ruby/JS method chains (`.label.split`, `f.label`, `descriptor.label`),
  # string i18n keys (`'x.label'`) and the `<label>` element — none of which match.
  [/\.label(?=\.(text-bg-|label-))/, '.badge'],

  # buttons / forms / inputs
  [/\bbtn-default\b/, 'btn-outline-secondary'],
  [/\binput-group-addon\b/, 'input-group-text'],
  [/\bhelp-block\b/, 'form-text'],
  [/\bcontrol-label\b/, 'form-label'],
  [/(?<![\w-])form-group(?![\w-])/, 'mb-3'],     # NOT no-label-form-group
  [/\bi-checks\b/, 'form-check-input'],
  # NB: BS3 responsive-visibility (visible-xs-block / hidden-xs) is NOT codemodded — its BS5
  # equivalents are MULTI-class (d-block d-sm-none / d-none d-sm-block), and a space-separated
  # expansion breaks HAML dot-notation (`.foo.d-block d-sm-none` makes `d-sm-none` inline text).
  # The 3 sites (layouts/_top_navbar, surveys/_form ×2) were hand-converted to dot-joined classes.
]

# hidden (the CSS class only) -> d-none, dot-notation only, NOT .hidden-xs (handled above anyway)
HIDDEN_DOT = [/\.hidden(?![\w-])/, '.d-none']

# ---- data-* attribute transforms (HAML only) ----------------------------------------------
BS_TOGGLE_VALUES = %w[modal dropdown collapse tab pill popover tooltip button buttons].freeze
DATA_KEYS = %w[target dismiss parent placement content container html trigger].freeze

def rewrite_data_attrs(text)
  # data-toggle -> data-bs-toggle ONLY for bootstrap values (footable's data-toggle="true" survives)
  text = text.gsub(/(["'])data-toggle\1(\s*(?:=>|:)\s*)(["'])(#{BS_TOGGLE_VALUES.join('|')})\3/) do
    %(#{$1}data-bs-toggle#{$1}#{$2}#{$3}#{$4}#{$3})
  end
  # other data-* component keys -> data-bs-* (values are ids / modal / alert / top — always safe)
  DATA_KEYS.each do |k|
    text = text.gsub(/(["'])data-#{k}\1/, "\\1data-bs-#{k}\\1")
  end
  # drop data-original-title (BS5 reads the title attr / data-bs-title); always followed by another attr
  text = text.gsub(/["']data-original-title["']\s*(?:=>|:)\s*["'][^"']*["']\s*,\s*/, '')
  text
end

# ---- caret element deletion (HAML only): drop lines that are ONLY a caret element -----------
def strip_caret_lines(text)
  text.each_line.reject { |l| l =~ /\A\s*%[a-z]+\.caret\s*\z/ }.join
end

def apply_class_rules(text, rules)
  rules.each { |re, rep| text = text.gsub(re, rep) }
  text
end

def process(path, kind)
  orig = File.read(path)
  text = orig.dup
  text = apply_class_rules(text, CLASS_RULES)
  re, rep = HIDDEN_DOT
  text = text.gsub(re, rep)
  if kind == :haml
    text = rewrite_data_attrs(text)
    text = strip_caret_lines(text)
  end
  if kind == :js
    text = text.gsub(/theme:\s*'explorer'/, "theme: 'explorer-fa4'")
  end
  if text != orig
    File.write(path, text)
    true
  else
    false
  end
end

changed = Hash.new(0)
{ haml: haml_files, scss: scss_files, js: js_files }.each do |kind, files|
  files.each do |p|
    changed[kind] += 1 if process(p, kind)
  end
end

puts "bs5_flip codemod complete:"
changed.each { |k, n| puts "  #{k}: #{n} files changed" }
puts "  (idempotent — re-run to confirm 0 further changes)"
