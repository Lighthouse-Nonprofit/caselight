require 'rails_helper'

RSpec.describe FamiliesHelper, type: :helper do
  describe '#family_member_list' do
    let(:object) do
      double('family', female_children_count: 1, male_children_count: 2, female_adult_count: 3, male_adult_count: 4)
    end
    before { allow(helper).to receive(:params).and_return({ locale: 'en' }) }
    subject(:markup) { helper.family_member_list(object) }

    it 'returns a single, self-contained, NON-empty <ul>' do
      expect(markup).to match(%r{\A<ul[^>]*>.+</ul>\z}m)
      expect(markup).not_to include('<ul class="family-members-list"></ul>')
    end

    it 'nests every <li> inside the <ul>' do
      outside = markup.sub(%r{<ul[^>]*>.*</ul>}m, '')
      expect(markup.scan('<li>').size).to eq(4)
      expect(outside).not_to include('<li')
    end

    it 'HTML-escapes each item' do
      allow(I18n).to receive(:t).and_call_original
      allow(I18n).to receive(:t).with('datagrid.columns.families.female').and_return('<script>x</script>')
      out = helper.family_member_list(object)
      expect(out).to include('&lt;script&gt;')
      expect(out).not_to include('<script>x</script>')
    end
  end
end
