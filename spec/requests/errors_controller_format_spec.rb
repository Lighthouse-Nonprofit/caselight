# frozen_string_literal: true
require 'rails_helper'

# Regression (all three boxes, 2026-09): scanner probes such as /phpinfo.php.json, /.env, /404.gif or
# /wp-json land on ErrorsController#show with a NON-HTML request format. Only errors/*.html.haml
# templates exist, so the error page itself raised ActionView::MissingTemplate and a plain 404 became
# a 500 (logged at FATAL, and a 409 on the tenanted boxes). The action now always renders the HTML page
# whatever format the request negotiated.
RSpec.describe 'Error pages for non-HTML request formats', type: :request do
  %w[/404.json /404.xml /404.yaml].each do |path|
    it "#{path} renders the themed HTML 404 page with status 404" do
      get path

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq('text/html')
      expect(response.body).to include('Go Home')
    end
  end

  %w[/404.gif /404.zip].each do |path|
    it "#{path} (a missing asset, or an archive probe) still gets the HTML 404 page" do
      get path

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq('text/html')
    end
  end

  it '/500.json renders the themed HTML 500 page with status 500' do
    get '/500.json'

    expect(response).to have_http_status(:internal_server_error)
    expect(response.media_type).to eq('text/html')
  end
end
