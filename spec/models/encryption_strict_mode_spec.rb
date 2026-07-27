# frozen_string_literal: true
require 'rails_helper'

# The 2026-07-26 strict-mode cutover: support_unencrypted_data=false is the app default (the
# Phase-4 migration window is closed — every tier verifies as ciphertext in every tenant). A
# non-envelope value in an encrypted column now RAISES on read instead of being silently
# tolerated; only the sanctioned migration rakes (encryption:backfill / reencrypt_client_names)
# re-enable the window, for their own process.
RSpec.describe 'AR Encryption strict mode (cutover 2026-07-26)', type: :model do
  after(:each) { ClientHistory.delete_all rescue nil }

  it 'ships strict: support_unencrypted_data is OFF by default' do
    expect(ActiveRecord::Encryption.config.support_unencrypted_data).to be(false)
  end

  it 'raises Errors::Decryption when an encrypted column holds planted plaintext' do
    client = create(:client)
    conn = Client.connection
    conn.execute(
      "UPDATE #{conn.quote_table_name(Client.table_name)} " \
      "SET rejected_note = #{conn.quote('PLAINTEXT-STRAGGLER')} " \
      "WHERE id = #{conn.quote(client.id)}"
    )

    expect { Client.find(client.id).rejected_note }
      .to raise_error(ActiveRecord::Encryption::Errors::Decryption)
  end

  it 'the migration rakes re-open the window for their own process (source-pinned)' do
    src = File.read(Rails.root.join('lib/tasks/encryption.rake'))
    %w[backfill reencrypt_client_names].each do |task|
      body = src[/task #{task}: :environment do.*?ActiveRecord::Encryption\.config\.support_unencrypted_data = true/m]
      expect(body).to be_present, "encryption:#{task} lost its strict-mode window (stragglers would be unfixable)"
    end
  end
end
