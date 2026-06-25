# frozen_string_literal: true
require 'rails_helper'

# Phase 4 Tier 2 — field-level encryption-at-rest regression specs for ADDRESS / LOCATION PII
# (FedRAMP SC-28, SOC 2 C1.1). Proves the 10 Tier-2 columns (Client x8: current_address, school_name,
# house_number, street_number, village, commune, district, live_with; Family#address; Partner#address)
# are encrypted (transparent decrypt on read; ciphertext envelope in the raw DB column), were widened
# string->text, and every now-unsearchable query site was removed: the eight Client *_like scopes, the
# village/commune iLIKE clauses in Client.filter, the ClientGrid current_address/school_name filters +
# current_address order:, the advanced-search text-field arrays (rule_fields/client_fields), the
# Family/Partner address_like scopes, and the Family/Partner grid :address filters. Also asserts the
# Api::ClientsController compare guard no longer admits village/commune-only requests.
#
# Runs in tenant 'app' (spec_helper before(:each) switches there). Client saves write a ClientHistory
# doc to Mongo via after_save :create_client_history; DatabaseCleaner is active_record-only, so we clean
# ClientHistory ourselves around examples that create Clients (default_scope is tenant 'app', so a plain
# delete_all only touches this tenant's docs). Mirrors spec/models/tier1_encryption_spec.rb.
RSpec.describe 'Tier 2 address/location PII encryption at rest (SC-28)', type: :model do
  # raw, un-decrypted column value straight from Postgres (bypasses the model's transparent decrypt)
  def raw_column(model, id, col)
    conn = model.connection
    conn.select_value(
      "SELECT #{conn.quote_column_name(col)} FROM #{conn.quote_table_name(model.table_name)} " \
      "WHERE #{conn.quote_column_name(model.primary_key)} = #{conn.quote(id)}"
    )
  end

  CLIENT_TIER2_COLUMNS = %i[
    current_address school_name house_number street_number village commune district live_with
  ].freeze

  describe 'declared encrypted attributes' do
    it 'encrypts the eight Client address/location columns' do
      expect(Client.encrypted_attributes).to include(*CLIENT_TIER2_COLUMNS)
    end

    it 'encrypts Family#address' do
      expect(Family.encrypted_attributes).to include(:address)
    end

    it 'encrypts Partner#address' do
      expect(Partner.encrypted_attributes).to include(:address)
    end

    it 'widened the eight Client columns to text so non-deterministic ciphertext fits' do
      CLIENT_TIER2_COLUMNS.each do |col|
        expect(Client.columns_hash[col.to_s].type).to eq(:text), "expected clients.#{col} to be :text"
      end
    end

    it 'widened families.address to text' do
      expect(Family.columns_hash['address'].type).to eq(:text)
    end

    it 'widened partners.address to text' do
      expect(Partner.columns_hash['address'].type).to eq(:text)
    end
  end

  describe 'round-trip + raw-ciphertext (Client)' do
    after { ClientHistory.delete_all }

    it 'decrypts transparently on read but stores ciphertext in every raw column' do
      values = {
        current_address: '12 Maple Street, Apt 4',
        school_name:     'Lincoln Elementary School',
        house_number:    '12B',
        street_number:   'Street 271',
        village:         'Riverside Village',
        commune:         'Sangkat Toul',
        district:        'Khan Daun Penh',
        live_with:       'Maternal grandmother'
      }
      client = create(:client, values)

      reloaded = Client.find(client.id)
      values.each do |col, plaintext|
        expect(reloaded.public_send(col)).to eq(plaintext), "expected #{col} to decrypt to #{plaintext.inspect}"
        raw = raw_column(Client, client.id, col)
        expect(raw).to be_present
        expect(raw).not_to eq(plaintext), "expected raw clients.#{col} to be ciphertext, not plaintext"
      end
    end
  end

  describe 'round-trip + raw-ciphertext (Family)' do
    it 'decrypts address transparently on read but stores ciphertext in the raw column' do
      plaintext = '12 Riverside Ave, Apt 3, San Luis Obispo, CA 93401'
      family = create(:family, :kinship, address: plaintext)

      reloaded = Family.find(family.id)
      expect(reloaded.address).to eq(plaintext)

      raw = raw_column(Family, family.id, :address)
      expect(raw).to be_present
      expect(raw).not_to eq(plaintext)
    end
  end

  describe 'round-trip + raw-ciphertext (Partner)' do
    it 'decrypts address transparently on read but stores ciphertext in the raw column' do
      plaintext = '500 Mission St, Suite 200, San Francisco, CA 94105'
      partner = create(:partner, address: plaintext)

      reloaded = Partner.find(partner.id)
      expect(reloaded.address).to eq(plaintext)

      raw = raw_column(Partner, partner.id, :address)
      expect(raw).to be_present
      expect(raw).not_to eq(plaintext)
    end
  end

  describe 'dropped query sites (cannot search/sort an encrypted column)' do
    it 'removed the eight Client *_like scopes' do
      %i[current_address_like school_name_like house_number_like street_number_like
         village_like commune_like district_like live_with_like].each do |scope_name|
        expect(Client).not_to respond_to(scope_name), "expected Client.#{scope_name} to be removed"
      end
    end

    it 'Client.filter no longer builds an iLIKE on the encrypted village/commune columns' do
      sql = Client.filter(village: 'Riverside', commune: 'Sangkat').to_sql.downcase
      expect(sql).not_to include('village')
      expect(sql).not_to include('commune')
    end

    it 'ClientGrid no longer filters current_address / school_name' do
      filter_names = ClientGrid.filters.map(&:name)
      expect(filter_names).not_to include(:current_address)
      expect(filter_names).not_to include(:school_name)
    end

    it 'ClientGrid does not ORDER BY the encrypted current_address column' do
      current_address_col = ClientGrid.columns.find { |c| c.name == :current_address }
      expect(current_address_col).to be_present # display column kept (renders decrypted value)
      expect(current_address_col.order).to be_falsey # ORDER BY clients.current_address removed
    end

    it 'advanced-search rule_fields no longer exposes the Tier 2 address text fields' do
      text_fields = AdvancedSearches::RuleFields.new.send(:text_type_list)
      %w[house_number street_number village commune district school_name].each do |f|
        expect(text_fields).not_to include(f), "expected rule_fields text list to drop #{f}"
      end
      # NB given_name/family_name/local_* were moved out of text_type_list into encrypted_name_type_list
      # by Tier 4 (deterministic encryption => equality-only, see tier4_encryption_spec). This Tier 2 spec
      # only owns the ADDRESS fields; it no longer asserts the names live in the substring text list.
      expect(text_fields).to include('slug', 'referral_phone')
    end

    it 'advanced-search client_fields no longer exposes school_name as a text field' do
      text_fields = AdvancedSearches::ClientFields.new.send(:text_type_list)
      expect(text_fields).not_to include('school_name')
      # given_name/family_name moved to encrypted_name_type_list by Tier 4 (see tier4_encryption_spec).
      expect(text_fields).to include('family', 'slug')
    end

    it 'removed Family.address_like' do
      expect(Family).not_to respond_to(:address_like)
    end

    it 'removed Partner.address_like (but kept the Tier 3 contact_person_*_like scopes)' do
      expect(Partner).not_to respond_to(:address_like)
      expect(Partner).to respond_to(:contact_person_name_like)
      expect(Partner).to respond_to(:contact_person_email_like)
      expect(Partner).to respond_to(:contact_person_mobile_like)
    end

    it 'FamilyGrid no longer filters address but keeps the display column' do
      expect(FamilyGrid.filters.map(&:name)).not_to include(:address)
      expect(FamilyGrid.columns.map(&:name)).to include(:address)
    end

    it 'PartnerGrid no longer filters address but keeps the display column + contact_person filters' do
      filter_names = PartnerGrid.filters.map(&:name)
      expect(filter_names).not_to include(:address)
      expect(filter_names).to include(:contact_person_name, :contact_person_email, :contact_person_mobile)
      expect(PartnerGrid.columns.map(&:name)).to include(:address)
    end
  end

  describe 'Api::ClientsController compare guard (encrypted village/commune no longer over-returns)' do
    it 'does not admit a village/commune-only request into Client.filter' do
      controller = Api::ClientsController.new
      # village/commune are now encrypted -> dropped from the guard; with only those keys present,
      # find_client_by must return [] rather than falling through to Client.filter (which would return
      # `all`). given_name still admits.
      expect(controller.send(:find_client_by, { village: 'X', commune: 'Y' })).to eq([])
      expect(controller.send(:find_client_by, {}).respond_to?(:empty?)).to be_truthy
    end
  end
end
