# Data-task batch D6 — client-direct email, feature-flipped on SMTP config (owner:
# "build out the direct email client, but have it be a feature flip on SMTP config,
# and default to case team, staff side"). email is contact PII: text (ciphertext
# overflows varchar) + non-deterministic encrypts on the model (Tier 2, the
# address/contact tier). notify_consent DEFAULTS FALSE — no consent recorded, no mail.
class AddClientEmailAndConsent < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :email, :text
    add_column :clients, :notify_consent, :boolean, null: false, default: false
  end
end
