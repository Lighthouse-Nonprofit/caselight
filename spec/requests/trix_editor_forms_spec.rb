# frozen_string_literal: true
require 'rails_helper'

# POAM-017a — the Trix editor replaces TinyMCE 4 on the three rich-text authoring fields
# (Domain#description, ProgressNote#response, ProgressNote#additional_note).
#
# Server-side proof of the swap (the in-browser editor behavior is covered by the manual
# Playwright gate in the PR):
#   1. the forms render a <trix-editor> bound to a hidden input (no TinyMCE textarea),
#   2. legacy TinyMCE-authored HTML round-trips: it loads into the hidden input on edit,
#      and Trix-shaped HTML (<div>-block markup) saves and renders through the unchanged
#      render_rich_text sanitizer with formatting preserved.
RSpec.describe 'Trix rich-text editor forms (POAM-017a)', type: :request do
  include Devise::Test::IntegrationHelpers
  let!(:admin) { create(:user, :admin) }
  before { sign_in admin }

  describe 'domains form' do
    it 'renders a trix-editor bound to the description hidden input (and no TinyMCE hook)' do
      get new_domain_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<trix-editor')
      # HAML emits single-quoted attributes; Rails form helpers emit double-quoted.
      expect(response.body).to match(/input=['"]domain_description_trix_input['"]/)
      # attribute order varies (an explicit id: option renders first) — assert both within one tag
      expect(response.body).to match(/<input(?=[^>]*type="hidden")[^>]*id="domain_description_trix_input"/)
      expect(response.body).not_to include('textarea.tinymce')
    end

    it 'loads legacy TinyMCE-authored HTML into the hidden input on edit' do
      legacy = '<p>Legacy <strong>bold</strong></p><ul><li>first</li><li>second</li></ul>'
      domain = create(:domain, description: legacy)
      get edit_domain_path(domain)
      expect(response).to have_http_status(:ok)
      # hidden_field HTML-escapes its value attribute
      expect(response.body).to include(ERB::Util.html_escape(legacy))
    end

    it 'saves Trix-shaped HTML and renders it through the sanitizer with formatting intact' do
      domain = create(:domain, description: '<p>old</p>')
      trix_html = '<div>Edited <strong>bold</strong> and <em>italic</em></div><ul><li>kept</li></ul>'
      patch domain_path(domain), params: { domain: { description: trix_html } }
      expect(domain.reload.description).to eq(trix_html)

      get domains_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<strong>bold</strong>')
      expect(response.body).to include('<em>italic</em>')
      expect(response.body).to include('<li>kept</li>')
    end
  end

  describe 'progress note form' do
    let(:client) { create(:client, able_state: 'Accepted') }

    it 'renders trix-editors bound to both note hidden inputs (and no TinyMCE hook)' do
      get new_client_progress_note_path(client)
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/input=['"]progress_note_response_trix_input['"]/)
      expect(response.body).to match(/input=['"]progress_note_additional_note_trix_input['"]/)
      expect(response.body.scan('<trix-editor').size).to eq(2)
      expect(response.body).not_to include('textarea.tinymce')
    end

    it 'renders Trix-shaped note HTML through the unchanged sanitizer' do
      trix_html = '<div>Client is <strong>stable</strong></div><ul><li>follow up</li></ul>'
      note = create(:progress_note, client: client, user: admin,
                    response: trix_html, additional_note: '<div><em>aside</em></div>')
      get client_progress_note_path(client, note)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<strong>stable</strong>')
      expect(response.body).to include('<li>follow up</li>')
      expect(response.body).to include('<em>aside</em>')
    end
  end
end
