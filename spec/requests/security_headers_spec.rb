# Phase 1 (transport, headers, secrets) security regression specs.
# Guards the hardened response headers, the report-only CSP, CORS removal, and log redaction
# so a future change can't silently regress them. Maps: FedRAMP SC-7/SC-8/SI, SOC 2 CC6.6/CC6.7.
RSpec.describe 'Security baseline', type: :request do
  describe 'response security headers' do
    # The Devise login page renders unauthenticated and carries the global headers.
    before { get '/users/sign_in' }

    it 'sends X-Frame-Options: SAMEORIGIN (anti-clickjacking)' do
      expect(response.headers['X-Frame-Options']).to eq('SAMEORIGIN')
    end

    it 'sends X-Content-Type-Options: nosniff' do
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
    end

    it 'sends a strict Referrer-Policy' do
      expect(response.headers['Referrer-Policy']).to eq('strict-origin-when-cross-origin')
    end

    it 'disables legacy cross-domain policies' do
      expect(response.headers['X-Permitted-Cross-Domain-Policies']).to eq('none')
    end

    it 'ships a Content-Security-Policy in report-only mode (not yet enforced)' do
      report_only = response.headers['Content-Security-Policy-Report-Only']
      expect(report_only).to be_present
      expect(report_only).to include("default-src 'self'")
      expect(report_only).to include("object-src 'none'")
      expect(report_only).to include("frame-ancestors 'self'")
      # Still report-only: no enforcing CSP header yet.
      expect(response.headers['Content-Security-Policy']).to be_blank
    end

    it 'does not advertise wide-open CORS (rack-cors removed)' do
      expect(response.headers['Access-Control-Allow-Origin']).to be_nil
    end
  end

  describe 'log parameter redaction' do
    let(:filtered) { Rails.application.config.filter_parameters }

    it 'redacts credentials from logs' do
      expect(filtered).to include(:passw, :token, :secret)
    end

    it 'redacts government / financial identifiers and DOB' do
      expect(filtered).to include(:ssn, :passport, :date_of_birth)
    end

    it 'redacts contact and location PII' do
      expect(filtered).to include(:email, :phone, :address)
    end
  end
end
