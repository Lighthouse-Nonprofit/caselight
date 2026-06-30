require 'rails_helper'

RSpec.describe CustomFormBuilderHelper, type: :helper do
  describe '#display_custom_properties' do
    it 'renders an Array (checkbox/multi-select) value as escaped <strong> chips without raising' do
      out = helper.display_custom_properties(['<i>x</i>', 'ok', ''])
      expect(out).to be_html_safe
      expect(out).to include('<strong class="label label-margin">&lt;i&gt;x&lt;/i&gt;</strong>')
      expect(out).to include('<strong class="label label-margin">ok</strong>')
      expect(out).not_to include('<i>x</i>')
      expect(out.scan('label-margin').size).to eq(2) # blank dropped
    end

    it 'keeps a plain String HTML-escaped (no stored XSS)' do
      out = helper.display_custom_properties('<script>alert(1)</script>')
      expect(out).to eq('<span>&lt;script&gt;alert(1)&lt;/script&gt;</span>')
      expect(out).to be_html_safe
    end

    it 'converts newlines to a <br> while keeping text escaped' do
      expect(helper.display_custom_properties("line1\nline2")).to match(%r{\A<span>line1<br\s*/?>line2</span>\z})
    end

    it 'formats a whole-date value' do
      expect(helper.display_custom_properties('2024-03-05')).to eq('<span>March 05, 2024</span>')
      expect(helper.display_custom_properties('2024/3/5')).to eq('<span>March 05, 2024</span>')
    end

    it 'does NOT 500 on a date-shaped-but-invalid value (renders escaped text)' do
      expect { helper.display_custom_properties('2024-13-99') }.not_to raise_error
      expect(helper.display_custom_properties('2024-13-99')).to eq('<span>2024-13-99</span>')
    end

    it 'does NOT mangle free text containing a date substring' do
      expect(helper.display_custom_properties('Arrived 2024-03-15 by bus'))
        .to eq('<span>Arrived 2024-03-15 by bus</span>')
    end

    it 'renders nil as an empty span without raising' do
      expect(helper.display_custom_properties(nil)).to eq('<span></span>')
    end
  end
end
