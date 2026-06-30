# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Assessment Domain description sanitization', type: :request do
  include Devise::Test::IntegrationHelpers
  let!(:admin) { create(:user, :admin) }
  before { sign_in admin }

  it 'renders allowed rich-text but strips active content on domains#index' do
    create(:domain, description: %q{<strong>Safe</strong><p>P</p><script>alert('x')</script><img src=x onerror=alert(1)>})
    get domains_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<strong>Safe</strong>')
    expect(response.body).to include('<p>P</p>')
    expect(response.body).not_to include("<script>alert('x')</script>")
    expect(response.body).not_to match(/onerror\s*=/i)
  end
end
