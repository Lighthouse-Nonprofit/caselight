# frozen_string_literal: true
require 'rails_helper'

# Unit 7 — proves render_rich_text (app/helpers/rich_text_helper.rb) is the single,
# safe rich-text render path that replaced the 5 bare `sanitize(...)` view sites
# (follows PR #57's XSS hardening).
#
# Non-regression: legit TinyMCE formatting (bold, links, lists, tables) SURVIVES.
# Security: <script>, on* handlers, javascript: hrefs, and <style> are STRIPPED.
# Contract: nil/blank -> safe empty String; the result is html_safe and NOT
# double-escaped (so views can `= render_rich_text(x)` without re-sanitizing).
#
# type: :helper is inferred from spec/helpers/ (config.infer_spec_type_from_file_location!),
# which mixes RichTextHelper onto the `helper` proxy.
RSpec.describe RichTextHelper, type: :helper do
  describe '#render_rich_text' do
    context 'keeps legitimate TinyMCE formatting' do
      it 'preserves <strong> (bold)' do
        out = helper.render_rich_text('<strong>Important</strong>')
        expect(out).to include('<strong>Important</strong>')
      end

      it 'preserves <a href> links' do
        out = helper.render_rich_text('<a href="https://example.org">link</a>')
        expect(out).to include('href="https://example.org"')
        expect(out).to include('>link</a>')
      end

      it 'preserves <ul>/<li> list structure' do
        out = helper.render_rich_text('<ul><li>one</li><li>two</li></ul>')
        expect(out).to include('<ul>')
        expect(out).to include('<li>one</li>')
        expect(out).to include('<li>two</li>')
      end

      it 'preserves table structure (additive widening over the Rails default)' do
        out = helper.render_rich_text(
          '<table><tbody><tr><td colspan="2">cell</td></tr></tbody></table>'
        )
        expect(out).to include('<table>')
        expect(out).to include('<td colspan="2">cell</td>')
      end
    end

    context 'strips dangerous content' do
      it 'strips <script> tags (and does not execute/emit them)' do
        out = helper.render_rich_text('<p>hi</p><script>alert(1)</script>')
        expect(out).to include('<p>hi</p>')
        # The <script> ELEMENT is removed (no executable node); loofah keeps the
        # inner TEXT as an inert text node — byte-identical to the bare `sanitize`
        # this replaced. The XSS property is "no <script> element", not "no 'alert'
        # substring anywhere in the escaped text".
        expect(out).not_to include('<script')
        expect(out).to eq('<p>hi</p>alert(1)')
      end

      it 'strips on* event handler attributes' do
        out = helper.render_rich_text('<img src="x" onerror="alert(1)">bad')
        expect(out).not_to include('onerror')
        expect(out).not_to include('alert(1)')
      end

      it 'neutralizes javascript: hrefs' do
        out = helper.render_rich_text('<a href="javascript:alert(1)">x</a>')
        expect(out).not_to include('javascript:')
      end

      it 'strips <style> blocks' do
        out = helper.render_rich_text('<style>body{display:none}</style><p>ok</p>')
        # The <style> ELEMENT is removed; loofah keeps the inner CSS as an inert
        # text node — byte-identical to the bare `sanitize` this replaced. No
        # <style> element means the CSS cannot apply, which is the XSS property.
        expect(out).not_to include('<style')
        expect(out).to eq('body{display:none}<p>ok</p>')
      end

      it 'drops the style attribute (CSS-injection surface)' do
        out = helper.render_rich_text('<p style="color:red">x</p>')
        expect(out).not_to include('style=')
        expect(out).to include('<p>x</p>')
      end

      it 'drops <img> per the documented pilot narrowing' do
        out = helper.render_rich_text('<p>see</p><img src="https://tracker/pixel.gif">')
        expect(out).not_to include('<img')
        expect(out).to include('<p>see</p>')
      end
    end

    context 'nil / blank input' do
      it 'returns a safe empty String for nil' do
        out = helper.render_rich_text(nil)
        expect(out).to eq('')
        expect(out).to be_html_safe
      end

      it 'returns a safe empty String for an empty String' do
        out = helper.render_rich_text('')
        expect(out).to eq('')
        expect(out).to be_html_safe
      end

      it 'returns a safe empty String for whitespace-only input' do
        out = helper.render_rich_text('   ')
        expect(out).to eq('')
        expect(out).to be_html_safe
      end
    end

    context 'html-safety contract' do
      it 'returns an html_safe String' do
        expect(helper.render_rich_text('<strong>x</strong>')).to be_html_safe
      end

      it 'does not double-escape safe markup (renders as tags, not &lt;strong&gt;)' do
        out = helper.render_rich_text('<strong>x</strong>')
        expect(out).not_to include('&lt;strong&gt;')
        expect(out).to include('<strong>x</strong>')
      end
    end
  end
end
