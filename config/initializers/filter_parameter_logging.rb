# Be sure to restart your server when you modify this file.

# Log redaction — FedRAMP AU-3 / SI-11, SOC 2 CC6.7 / P-controls. Filters are case-insensitive
# SUBSTRING matches applied at any nesting depth, so e.g. :email also covers client[contact_email].
# Deliberately NOT filtering bare :name — it would redact org/program/custom-field names and gut
# log usefulness. The bulk dynamic-form PII (CustomFieldProperty values) is addressed by field-level
# encryption in Phase 4; this protects the obvious identifiers from the request/parameter logs.
Rails.application.config.filter_parameters += [
  # Credentials & secrets
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :private_key,
  # Government / financial identifiers
  :ssn, :social_security, :national_id, :passport, :tax_id, :account_number, :routing,
  # Date of birth
  :date_of_birth, :dob, :birthday, :birthdate,
  # Contact details
  :email, :phone, :telephone, :mobile, :fax,
  # Location
  :address, :street, :postal, :zipcode, :zip_code
]
