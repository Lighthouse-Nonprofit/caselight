# frozen_string_literal: true
require 'rails_helper'

# UNIT 7 — XSS / html-safety REGRESSION GUARD (references PR #57).
#
# PR #57 fixed a cluster of stored-XSS / buffer-leak defects: raw `.html_safe` on model &
# user attributes, the `content_tag ... do ... concat ... end` shared-buffer double-render,
# and ad-hoc `sanitize()`/`raw()` in views. Unit 7 centralizes ALL rich-text rendering behind
# RichTextHelper#render_rich_text (app/helpers/rich_text_helper.rb — an explicit sanitize
# allowlist; both helper modules mix into every view) and installs THIS spec so
# CI (which runs no rubocop) fails the build if any of those unsafe patterns are reintroduced.
#
# This is a REGRESSION GUARD, not a fixer: it walks the app/ tree, reads file text, and asserts
# the forbidden patterns are absent EXCEPT for a small, documented allowlist of legitimate uses
# (developer-controlled I18n copy, a generated QR SVG). It needs no DB and is fast/deterministic.
#
# If a NEW file legitimately needs one of these patterns, add an ALLOWLIST entry with a reason —
# do not loosen a regex. Per-file+per-pattern allowlisting keyed by a stable repo-relative path
# means a NEW offending file is still caught even though an allowlisted sibling exists.
RSpec.describe 'Rich-text / html-safety regression guard (Unit 7)' do
  APP = Rails.root.join('app')

  # ---- Allowlist ---------------------------------------------------------------------------
  # Each entry: [repo-relative path, rule-key, reason]. An offender is permitted ONLY if its
  # (path, rule) pair appears here. Paths are relative to Rails.root and use forward slashes.
  ALLOWLIST = [
    # (a) .html_safe on a bare empty-string LITERAL inside the one sanctioned rich-text helper.
    # render_rich_text returns `"".html_safe` for blank input so an empty description renders as
    # an empty html_safe String (matching pre-Unit-7 behavior). The literal carries no data, so
    # this is not the PR #57 attribute-html_safe pattern — but it is allowlisted BY PATH so no
    # OTHER file can borrow the empty-literal idiom to smuggle .html_safe past the guard.
    ['app/helpers/rich_text_helper.rb', :html_safe,
     'render_rich_text returns "".html_safe for blank input — empty string LITERAL, no data.'],
    # (c) raw() in views — two legitimate, un-sanitizable classes:
    ['app/views/two_factor_settings/show.html.haml', :raw_in_view,
     'raw @qr_svg — server-generated 2FA QR SVG (RQRCode output); sanitize would strip the SVG.'],
    ['app/views/kaminari/_first_page.html.haml', :raw_in_view,
     "raw(t 'views.pagination.first') — developer-controlled I18n pagination label (« etc.)."],
    ['app/views/kaminari/_prev_page.html.haml',  :raw_in_view,
     "raw(t 'views.pagination.previous') — developer-controlled I18n pagination label."],
    ['app/views/kaminari/_next_page.html.haml',  :raw_in_view,
     "raw(t 'views.pagination.next') — developer-controlled I18n pagination label."],
    ['app/views/kaminari/_last_page.html.haml',  :raw_in_view,
     "raw(t 'views.pagination.last') — developer-controlled I18n pagination label."],
    ['app/views/kaminari/_gap.html.haml',        :raw_in_view,
     "raw(t 'views.pagination.truncate') — developer-controlled I18n pagination label (…)."],
  ].freeze

  # Fast membership check: is (relpath, rule) explicitly permitted?
  def allowlisted?(relpath, rule)
    ALLOWLIST.any? { |path, key, _reason| path == relpath && key == rule }
  end

  # Repo-relative, forward-slashed path for an absolute file under Rails.root.
  def relpath(file)
    Pathname.new(file).relative_path_from(Rails.root).to_s.tr('\\', '/')
  end

  # All view/helper/decorator source files we police.
  def source_files(*globs)
    globs.flat_map { |g| Dir.glob(APP.join(g)) }.select { |f| File.file?(f) }.sort
  end

  VIEW_GLOB      = 'views/**/*.haml'
  HELPER_GLOB    = 'helpers/**/*.rb'
  DECORATOR_GLOB = 'decorators/**/*.rb'

  # Strip a HAML/Ruby line's trailing comment and skip whole-line comments, so PROSE that merely
  # MENTIONS a forbidden token ("...do NOT use `content_tag :span do ... concat ...`", or the word
  # "sanitize" in a code comment) never trips a rule. We only need to defeat comment false-positives,
  # not build a full parser: drop lines whose first non-space char begins a comment (# for Ruby,
  # -# / #{...}-free `#` for HAML), and for inline code, cut at an unquoted ' #' / ' -#'.
  def code_lines(file)
    File.read(file, encoding: 'UTF-8').each_line.map do |line|
      stripped = line.lstrip
      next '' if stripped.start_with?('#')   # Ruby full-line comment
      next '' if stripped.start_with?('-#')  # HAML code comment
      next '' if stripped.start_with?('/')   # HAML markup comment
      # Cut an inline Ruby comment (best-effort: only when ' #' is clearly not inside a string).
      # Conservative: only strip when there is no quote on the line before the ' #'.
      if (idx = line.index(/\s#(?!\{)/)) && !line[0...idx].match?(/['"]/)
        line[0...idx]
      else
        line
      end
    end
  end

  # ---- Rule (a): .html_safe only on an I18n t()/I18n.t() call --------------------------------
  # PR #57's core defect was `<attr>.html_safe` (model/user data marked safe unescaped). We ALLOW
  # `.html_safe` ONLY when it is chained directly off a translation lookup — t('..')/I18n.t('..') —
  # which is developer-authored copy. Anything else (a variable, a model attribute, an interpolated
  # or concatenated string) fails the build.
  #
  # Permitted shape (anchored to end-of-expression): the token immediately before `.html_safe`
  # is `t('...')` / `t("...")` / `I18n.t('...')` / `I18n.t("...")`, optionally with extra args.
  HTML_SAFE_OK = /
    (?:I18n\.)?t          # t  or  I18n.t
    \s*\(\s*              # (
    ['"][^'"]*['"]        # a quoted key
    [^)]*                 # optional further args (interpolation, options)
    \)\s*
    \.html_safe\b
  /x

  # A bare EMPTY-STRING literal marked html_safe: `"".html_safe` / `''.html_safe` (optionally with
  # surrounding whitespace). Carries no data, so it is not the PR #57 attribute pattern. Permitted
  # ONLY in a path allowlisted for :html_safe (currently just the sanctioned rich-text helper), so
  # no other file can reuse the idiom to smuggle .html_safe past the guard.
  EMPTY_LITERAL_HTML_SAFE = /(?:""|'')\s*\.html_safe\b/

  it 'allows .html_safe ONLY on an I18n t()/I18n.t() translation call (PR #57 core fix)' do
    offenders = []
    source_files(VIEW_GLOB, HELPER_GLOB, DECORATOR_GLOB).each do |file|
      rel = relpath(file)
      code_lines(file).each_with_index do |line, i|
        next unless line.include?('.html_safe')
        next if line =~ HTML_SAFE_OK
        # Empty-string-literal .html_safe is allowed ONLY in a path allowlisted for :html_safe.
        next if line =~ EMPTY_LITERAL_HTML_SAFE && allowlisted?(rel, :html_safe)
        offenders << "#{rel}:#{i + 1}: #{line.strip}"
      end
    end
    expect(offenders).to be_empty, <<~MSG
      Found .html_safe on something other than an I18n t()/I18n.t() call.
      This is the exact stored-XSS pattern PR #57 removed: never call .html_safe on a model
      attribute, variable, or interpolated string. Sanitize rich text via render_rich_text(...)
      instead, or (for developer copy) chain .html_safe directly off t('...')/I18n.t('...').
      Offenders:
      #{offenders.join("\n")}
    MSG
  end

  # ---- Rule (b): no `content_tag ... do` block whose body contains a `concat` statement -------
  # The buffer-leak double-render: inside HAML's capture, `concat` appends to the OUTER page
  # buffer, so content_tag snapshots the partially-rendered page. Correct code builds the content
  # as a returned value (safe_join) and passes it as an argument. We flag any real `concat`
  # STATEMENT inside a `content_tag ... do ... end` block. Prose in comments is stripped by
  # code_lines, so the anti-pattern WARNING comment in custom_form_builder_helper.rb is ignored.
  it 'has no content_tag ... do block that calls concat (shared-buffer leak)' do
    offenders = []
    source_files(HELPER_GLOB, DECORATOR_GLOB, VIEW_GLOB).each do |file|
      rel   = relpath(file)
      lines = code_lines(file)
      open_depth = nil # non-nil while we are inside a content_tag ... do block
      lines.each_with_index do |line, i|
        if open_depth.nil?
          # Enter a block when a line opens `content_tag(...) do` (with or without |args|).
          # The `do` itself is ONE open level, so start at depth 1 — a plain body
          # statement then keeps depth at 1 and the block stays open until its matching
          # `end`. (Starting at 0 closed the block after the first non-opener body line,
          # letting a `stmt; concat x` leak — the exact PR #57 shape — slip through.)
          open_depth = 1 if line =~ /\bcontent_tag\b.*\bdo\b(\s*\|[^|]*\|)?\s*$/
        else
          # Track nested do/{ ... end/} shallowly so we know when the block closes.
          open_depth += line.scan(/\bdo\b|\{/).size
          open_depth -= line.scan(/\bend\b|\}/).size
          # A buffer-writing STATEMENT (line-initial `concat`/`safe_concat` call, not
          # `.concat` on an Array) inside the block. Both append to the OUTER capture
          # buffer and cause the shared-buffer double-render. (`<<` is intentionally NOT
          # matched — it is used legitimately ~15x for Array/String building elsewhere;
          # tracked as a documented residual, not a guard rule.)
          if line =~ /^\s*(?:safe_concat|concat)[\s(]/
            offenders << "#{rel}:#{i + 1}: #{line.strip}"
          end
          open_depth = nil if open_depth <= 0
        end
      end
    end
    expect(offenders).to be_empty, <<~MSG
      Found `concat` inside a `content_tag ... do` block — the shared-buffer double-render PR #57
      fixed. Build the tag content as a RETURNED value (e.g. safe_join([...])) and pass it as the
      content ARGUMENT to content_tag; never `concat` into the outer buffer from inside the block.
      Offenders:
      #{offenders.join("\n")}
    MSG
  end

  # ---- Rule (c): no bare raw() in views outside the allowlist --------------------------------
  # raw() bypasses escaping entirely. Only two legitimate classes remain (see ALLOWLIST): the
  # generated 2FA QR SVG and kaminari I18n pagination labels. Any other raw( in a view fails.
  it 'has no raw() in views outside the documented allowlist' do
    offenders = []
    source_files(VIEW_GLOB).each do |file|
      rel = relpath(file)
      next if allowlisted?(rel, :raw_in_view)
      code_lines(file).each_with_index do |line, i|
        next unless line =~ /\braw[\s(]/
        offenders << "#{rel}:#{i + 1}: #{line.strip}"
      end
    end
    expect(offenders).to be_empty, <<~MSG
      Found raw() in a view outside the allowlist. raw() disables HTML escaping — a stored-XSS
      vector for any user/model-derived string. Render rich text via render_rich_text(...) instead.
      If the content is genuinely un-sanitizable (a generated SVG) or developer-controlled I18n
      copy, add an explicit ALLOWLIST entry in this spec with a documented reason.
      Offenders:
      #{offenders.join("\n")}
    MSG
  end

  # ---- Rule (d): no bare sanitize() in views (must be render_rich_text) ----------------------
  # Unit 7 centralizes rich-text rendering: the 5 former sanitize() sites now call
  # render_rich_text, and NO view should call sanitize() directly (ad-hoc allowlists drift and
  # rot). render_rich_text is the single sanctioned entry point.
  it 'has no bare sanitize() in views (rich text must go through render_rich_text)' do
    offenders = []
    source_files(VIEW_GLOB).each do |file|
      rel = relpath(file)
      code_lines(file).each_with_index do |line, i|
        next unless line =~ /\bsanitize\(/
        offenders << "#{rel}:#{i + 1}: #{line.strip}"
      end
    end
    expect(offenders).to be_empty, <<~MSG
      Found a bare sanitize() call in a view. Rich-text HTML must be rendered through the single
      sanctioned helper render_rich_text(...) (RichTextHelper, app/helpers/rich_text_helper.rb),
      which owns the explicit tag/attribute allowlist. Replace `sanitize(x)` with `render_rich_text(x)`.
      Offenders:
      #{offenders.join("\n")}
    MSG
  end

  # ---- Positive assertion: render_rich_text is present at exactly the 5 known sites ----------
  # Guards the OTHER direction: if a refactor silently drops render_rich_text back to raw output
  # (or someone reintroduces sanitize under a new name), the count drifts and this fails.
  it 'routes exactly the 5 rich-text sites through render_rich_text' do
    hits = source_files(VIEW_GLOB).flat_map do |file|
      rel = relpath(file)
      File.read(file, encoding: 'UTF-8').each_line.each_with_index.filter_map do |line, i|
        "#{rel}:#{i + 1}" if line.include?('render_rich_text')
      end
    end
    expect(hits.size).to eq(5), <<~MSG
      Expected render_rich_text at exactly 5 view sites (domains/index, changelogs/show,
      assessments/_form, progress_notes/show x2). Found #{hits.size}:
      #{hits.join("\n")}
      If you intentionally added or removed a rich-text render site, update this count and the
      Unit-7 map together so the guard stays meaningful.
    MSG
  end
end
