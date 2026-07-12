# frozen_string_literal: true
require 'rails_helper'

# POAM-017f / 12C-2 — the in-app CSP violation collector. Browsers POST application/csp-report
# credential-less and token-less; the endpoint must accept that, log a PII-scrubbed structured
# line, throttle abuse (rack_attack), and never 500 on junk.
RSpec.describe 'CSP report collector', type: :request do
  let(:report) do
    {
      'csp-report' => {
        'document-uri' => 'https://cases.example.org/clients/cases-1?q=SECRET_PII',
        'violated-directive' => 'script-src',
        'effective-directive' => 'script-src',
        'blocked-uri' => 'https://evil.example.com/x.js?token=SECRET_TOKEN',
        'source-file' => 'https://cases.example.org/assets/application-abc.js',
        'line-number' => 42,
        'disposition' => 'report'
      }
    }.to_json
  end

  it 'accepts an unauthenticated, tokenless report and logs a scrubbed csp_violation line' do
    logged = []
    allow(Rails.logger).to receive(:warn) { |line| logged << line.to_s }

    post '/csp_reports', params: report, headers: { 'CONTENT_TYPE' => 'application/csp-report' }
    expect(response).to have_http_status(:no_content)

    line = logged.find { |l| l.include?('csp_violation') }
    expect(line).to be_present
    expect(line).to include('script-src')
    expect(line).to include('https://evil.example.com/x.js')
    # query strings are PII channels — scrubbed before logging
    expect(line).not_to include('SECRET_PII')
    expect(line).not_to include('SECRET_TOKEN')
  end

  it 'handles the inline blocked-uri token (a string, not a URL)' do
    body = { 'csp-report' => { 'violated-directive' => 'script-src', 'blocked-uri' => 'inline' } }.to_json
    post '/csp_reports', params: body, headers: { 'CONTENT_TYPE' => 'application/csp-report' }
    expect(response).to have_http_status(:no_content)
  end

  it 'swallows junk bodies without raising or logging' do
    logged = []
    allow(Rails.logger).to receive(:warn) { |line| logged << line.to_s }
    post '/csp_reports', params: 'not json {', headers: { 'CONTENT_TYPE' => 'application/csp-report' }
    expect(response).to have_http_status(:no_content)
    expect(logged.select { |l| l.include?('csp_violation') }).to be_empty
  end

  it 'rejects oversize bodies without parsing them' do
    post '/csp_reports', params: 'x' * 10.kilobytes, headers: { 'CONTENT_TYPE' => 'application/csp-report' }
    expect(response).to have_http_status(:no_content)
  end

  it 'does not route GET (the catch-all renders 404 rather than raising)' do
    get '/csp_reports'
    expect(response).to have_http_status(:not_found)
  end
end
