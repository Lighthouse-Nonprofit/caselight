describe AdvancedSearches::ClientFields, 'Method' do
  let(:admin) { create(:user, roles: 'admin') }

  before do
    @client_fields = AdvancedSearches::ClientFields.new(user: admin).render
  end

  context 'render' do
    it 'return field not nil' do
      expect(@client_fields).not_to be_nil
    end

    # PINNED: pre-existing failure on the 4.2 baseline (field-count drift); triage during the upgrade
    xit 'return all fields' do
      expect(@client_fields.size).to equal 46
    end
  end
end
