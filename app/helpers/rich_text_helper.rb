# frozen_string_literal: true

# RichTextHelper — Unit 7 (follows PR #57's XSS hardening).
#
# Single, centralized entry point for rendering TinyMCE-authored rich-text HTML
# stored on model attributes (domain descriptions, changelog descriptions,
# progress-note response/additional_note). Before Unit 7 each view called
# Rails' bare `sanitize(...)`, which relies on the *implicit* framework default
# allowlist. This helper makes the allowlist EXPLICIT so the accepted/stripped
# tag set is reviewable in one place and cannot drift, and so a CI guard
# (spec/lib/rich_text_guard_spec.rb) can forbid any new bare sanitize()/raw()/
# .html_safe rich-text render sites outside this helper.
#
# Security properties (delegated to rails-html-sanitizer / loofah's
# SafeListSanitizer, same engine `sanitize` already used):
#   - <script>, <style>, and all on* event-handler attributes are STRIPPED.
#   - javascript:/data: (and other unsafe) protocols in href/src are neutralized
#     by loofah's protocol scrubbing.
#   - Only the tags/attributes in the explicit allowlists below survive.
#
# Deliberate, security-motivated narrowing vs. the Rails default allowlist
# (called out in the PR so it is a conscious change, not a silent regression):
#   - `img` is NOT allowed. The Rails default permits <img src>, which is a
#     tracking-pixel / data-exfil beacon vector on PII-adjacent content. The
#     pilot org does not use inline images in these fields. To re-enable, add
#     'img' to RICH_TEXT_TAGS and 'src alt width height' to RICH_TEXT_ATTRIBUTES.
#   - `style` is NOT allowed (matches current behavior — the default `sanitize`
#     already strips it). It is the primary CSS-injection surface.
#
# Additive widenings vs. the Rails default (safe — allow more structure, no
# script surface):
#   - table markup (table/thead/tbody/tfoot/tr/td/th/caption + colspan/rowspan)
#     so TinyMCE tables survive.
#   - target/rel on <a> so external links can open safely.
#
# NO-REGRESSION GUARANTEE: RICH_TEXT_TAGS/RICH_TEXT_ATTRIBUTES are a strict
# SUPERSET of the Rails default allowlist MINUS the two documented denials
# (img, style). Every inline/text-semantic tag the bare `sanitize` used to keep
# (abbr, small, del, ins, mark, address, dfn, dl/dt/dd, kbd, samp, var, cite,
# time, acronym, big, tt) is retained so existing staff-authored content in the
# 5 render sites loses NO markup — verified against the exact production
# sanitizer (loofah 2.25.1 / rails-html-sanitizer 1.7.0). Only <img> and the
# style/on*/script surfaces are stripped.
module RichTextHelper
  # Superset of what these fields realistically contain (TinyMCE output), kept
  # at or above the Rails default floor so existing content is never regressed
  # (except the documented img/style denials above).
  RICH_TEXT_TAGS = %w[
    p br span div
    strong b em i u s strike sub sup
    blockquote pre code hr
    ul ol li
    a
    h1 h2 h3 h4 h5 h6
    table thead tbody tfoot tr td th caption
    abbr acronym address big cite dfn dl dt dd del ins
    kbd mark samp small time tt var
  ].freeze

  RICH_TEXT_ATTRIBUTES = %w[
    href title class
    colspan rowspan
    target rel
    datetime cite lang
  ].freeze

  # Render trusted-but-user-authored rich text with the explicit allowlist.
  # Returns an html_safe String. nil/blank input renders as an empty (html_safe)
  # String, matching the pre-Unit-7 behavior for empty descriptions
  # (`changelogs.description` defaults to ""). Callers must NOT chain .html_safe
  # onto the result — `sanitize` already returns an html_safe String.
  def render_rich_text(html)
    return "".html_safe if html.blank?

    sanitize(html.to_s, tags: RICH_TEXT_TAGS, attributes: RICH_TEXT_ATTRIBUTES)
  end
end
