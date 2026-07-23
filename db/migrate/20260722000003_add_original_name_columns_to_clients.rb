# UX round 3 (C1) — case-insensitive name search. `ignore_case: true` on the four
# deterministic name columns computes the ciphertext over the DOWNCASED value while Rails
# preserves the display casing in these `original_*` sidecar columns (required by the option).
# Purely additive; rows re-encrypt via `rake encryption:reencrypt_client_names CONFIRM=1`
# immediately after deploy (equality search on un-re-encrypted rows is covered by the
# `previous:` scheme declaration until then).
class AddOriginalNameColumnsToClients < ActiveRecord::Migration[8.0]
  def change
    add_column :clients, :original_given_name,        :text
    add_column :clients, :original_family_name,       :text
    add_column :clients, :original_local_given_name,  :text
    add_column :clients, :original_local_family_name, :text
  end
end
