# frozen_string_literal: true

require 'rails_helper'

# Production SMTP settings — mutual-exclusivity guard.
#
# `:tls`/`:ssl` (implicit TLS, port 465) and `:enable_starttls`/`:enable_starttls_auto` (an explicit
# STARTTLS upgrade, port 587) describe two different connection styles. mail >= 2.8 raises
#   ArgumentError: :enable_starttls and :tls are mutually exclusive
# if both are configured, which 500s EVERY delivery. On a tenanted box that 500 renders the themed
# error page in the public schema, so the tenant-boundary enforcement turns it into a **409** — the
# user sees a confusing conflict status for what is really a mail-config error.
#
# This went unnoticed for a long time because no box had SES credentials, so nothing ever attempted
# a send. It surfaced the first time a real password reset ran (slo4home, 2026-09-12).
#
# WHY A TEXT GUARD: these settings live in config/environments/production.rb, which cannot be loaded
# from the test environment without booting production. Asserting on the source is crude, but it
# catches exactly the regression that matters and needs no production boot.
RSpec.describe 'production SMTP settings' do
  let(:source) { Rails.root.join('config/environments/production.rb').read }
  let(:block) do
    m = source.match(/smtp_settings\s*=\s*\{(.+?)\n\s*\}/m)
    raise 'could not locate config.action_mailer.smtp_settings in production.rb' unless m

    m[1]
  end

  it 'does not set implicit TLS and STARTTLS at the same time' do
    implicit = block.match?(/^\s*(ssl|tls):\s*true/)
    starttls = block.match?(/^\s*enable_starttls(_auto)?:\s*true/)

    expect(implicit && starttls).to be(false),
                                   'production.rb sets BOTH implicit TLS (:ssl/:tls) and STARTTLS ' \
                                   '(:enable_starttls*). mail >= 2.8 raises ArgumentError on every ' \
                                   'delivery, which surfaces to users as a 409. Pick one: :ssl/:tls ' \
                                   'for port 465, or :enable_starttls_auto for port 587.'
  end

  it 'configures at least one transport-security mode (never plaintext SMTP)' do
    expect(block).to match(/^\s*(ssl|tls|enable_starttls(_auto)?):\s*true/)
  end

  it 'verifies the server certificate' do
    expect(block).not_to match(/VERIFY_NONE/),
                         'openssl_verify_mode: VERIFY_NONE accepts ANY certificate, which makes TLS ' \
                         'decorative against an active network attacker. These messages carry client ' \
                         'names and password-reset links.'
  end
end
