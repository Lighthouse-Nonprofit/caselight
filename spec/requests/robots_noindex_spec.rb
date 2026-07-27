# frozen_string_literal: true
require 'rails_helper'

# SECURITY.md pilot baseline: "noindex / not linked publicly; do not let it get crawled."
# The live box serves robots.txt from the DYNAMIC route (organizations#robots reading
# config/robots/<env>.txt — no static public/robots.txt ships; /public/* is gitignored and
# absent from the image). production.txt was allow-all (empty Disallow) until 2026-07-26.
# robots.txt is advisory either way — the X-Robots-Tag header is the enforcement layer.
RSpec.describe 'crawler defenses (noindex pilot baseline)', type: :request do
  it 'serves disallow-all from every robots config the dynamic route can ship' do
    %w[production staging development].each do |env|
      body = File.read(Rails.root.join('config', 'robots', "#{env}.txt"))
      expect(body).to match(/^Disallow: \/$/), "config/robots/#{env}.txt must disallow all"
    end
  end

  it 'never ships an overriding static robots.txt (it would shadow the route under static serving)' do
    # Local dev machines may carry an untracked copy; the REPO must not (gitignored via /public/*).
    tracked = `git -C #{Rails.root} ls-files public/robots.txt`.strip
    expect(tracked).to eq('')
  end

  it 'sends X-Robots-Tag: noindex on every controller response, signed-out included' do
    get '/users/sign_in'
    expect(response.headers['X-Robots-Tag']).to eq('noindex, nofollow')
  end

  it 'marks the layout with a robots meta tag' do
    get '/users/sign_in'
    expect(response.body).to include('name="robots"')
    expect(response.body).to include('noindex,nofollow')
  end
end
