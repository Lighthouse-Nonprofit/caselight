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

    it 'ships the tightened, nonce-based CSP (report-only soak until the 12C-3 flip)' do
      # ENFORCE_CSP is unset in test until 12C-3 flips the default -> assert whichever
      # header the boot-time flag selected (env_config memoizes at boot; don't flip in-spec).
      enforced = Rails.application.config.x.enforce_csp
      header_name = enforced ? 'Content-Security-Policy' : 'Content-Security-Policy-Report-Only'
      other_name  = enforced ? 'Content-Security-Policy-Report-Only' : 'Content-Security-Policy'
      csp = response.headers[header_name]
      expect(csp).to be_present
      expect(response.headers[other_name]).to be_blank

      expect(csp).to include("default-src 'self'")
      expect(csp).to include("object-src 'none'")
      expect(csp).to include("frame-ancestors 'self'")
      expect(csp).to include("frame-src 'none'")
      expect(csp).to include("form-action 'self'")
      expect(csp).to match(/script-src 'self' 'nonce-[A-Za-z0-9+\/=]+'/)
      expect(csp).to include("style-src 'self' 'unsafe-inline'")
      expect(csp).to include("img-src 'self' data:")
      expect(csp).to include("font-src 'self' data:")
      expect(csp).to include("connect-src 'self'")
      expect(csp).to include('report-uri /csp_reports')
      # the whole point of Unit 18:
      expect(csp).not_to include('unsafe-eval')
      expect(csp).not_to match(/script-src[^;]*unsafe-inline/)
      expect(csp).not_to match(/https:/)
    end

    it 'enforces by default, with ENFORCE_CSP=false as the shadow-mode kill switch' do
      # 12C-3 (2026-07-12): the code default is enforce; report_only derives from the flag.
      expect(Rails.application.config.x.enforce_csp).to be(true)
      expect(Rails.application.config.content_security_policy_report_only).to be(false)
      expect(response.headers['Content-Security-Policy']).to be_present
      expect(response.headers['Content-Security-Policy-Report-Only']).to be_blank
    end

    it 'mints a fresh script nonce per request (SecureRandom, not the session id)' do
      first = response.headers['Content-Security-Policy-Report-Only'].to_s +
              response.headers['Content-Security-Policy'].to_s
      get '/users/sign_in'
      second = response.headers['Content-Security-Policy-Report-Only'].to_s +
               response.headers['Content-Security-Policy'].to_s
      nonce = ->(h) { h[/'nonce-([^']+)'/, 1] }
      expect(nonce.call(first)).to be_present
      expect(nonce.call(second)).to be_present
      expect(nonce.call(first)).not_to eq(nonce.call(second))
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
