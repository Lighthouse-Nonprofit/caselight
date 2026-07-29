# frozen_string_literal: true

require 'rails_helper'

# POAM-019 (PR B2) — pins the WARM Chromium/Ferrum PDF surface. SKIPS (never fails) on runners
# without a chromium binary: the CI test-suite runner has no browser (that is why it runs the
# js-excluding subset); the built image and the dev container DO (Dockerfile bakes chromium as of
# this PR). So this spec is exercised by the local suite and by any in-image run — and the
# in-image render is what bootstrap deploy verification can call on.
RSpec.describe PdfRenderer do
  describe '.browser_path / .available?' do
    it 'resolves via BROWSER_PATH first, then the known binary locations' do
      # Pure logic check, runs everywhere: a bogus BROWSER_PATH is ignored (not executable).
      begin
        ENV['BROWSER_PATH'] = '/nonexistent/chromium'
        expect(described_class.browser_path).not_to eq('/nonexistent/chromium')
      ensure
        ENV.delete('BROWSER_PATH')
      end
    end
  end

  describe 'rendering', if: PdfRenderer.available? do
    it 'render_html produces a real PDF (magic bytes, non-trivial size)' do
      pdf = described_class.render_html('<!doctype html><html><body><h1>Warm surface</h1></body></html>')
      expect(pdf[0, 5]).to eq('%PDF-')
      expect(pdf.bytesize).to be > 1_000
    end

    it 'render_template renders through the self-contained pdf layout with assigns' do
      pdf = described_class.render_template(
        template: 'pdf/smoke',
        assigns:  { title: 'Smoke Report', rows: [%w[alpha 1], %w[beta 2]] }
      )
      expect(pdf[0, 5]).to eq('%PDF-')
      expect(pdf.bytesize).to be > 5_000 # styled layout + table renders more than a bare page
    end
  end

  describe 'when chromium is absent', unless: PdfRenderer.available? do
    it 'raises ChromiumMissing rather than failing obscurely' do
      expect { described_class.render_html('<html></html>') }
        .to raise_error(PdfRenderer::ChromiumMissing)
    end
  end
end
