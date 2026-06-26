# frozen_string_literal: true
require 'rails_helper'

# Phase 4 regression guard. Tier 3 widened users.email from :string to :text (so the ActiveRecord-Encryption
# ciphertext envelope fits). SimpleForm infers the input type from the COLUMN type, so a :text column renders
# as a resizable multi-line <textarea> — the login email box silently became drag-resizable.
# config/initializers/simple_form.rb#input_mappings maps these specific single-line attribute names
# (email -> :email, names/mobile/short-address -> :string) back to single-line inputs regardless of the
# column type. This spec locks the login-page email field in (the most visible instance); the mapping is
# global, so it covers the staff-name / mobile / client-name fields on the authenticated forms too.
#
# Runs in tenant 'app' (spec_helper switches there); the sign-in page is public.
RSpec.describe 'Login form input types (SimpleForm input_mappings over encrypted :text columns)', type: :request do
  it 'renders the sign-in email as a single-line <input type="email">, NOT a resizable <textarea>' do
    get new_user_session_path
    expect(response).to have_http_status(:ok)
    body = response.body

    # The email field must be a single-line email INPUT bound to user[email]...
    expect(body).to match(/<input[^>]*\bname="user\[email\]"/),
      'expected an <input> for user[email] on the sign-in page'
    expect(body).to match(/<input[^>]*\btype="email"[^>]*\bname="user\[email\]"|<input[^>]*\bname="user\[email\]"[^>]*\btype="email"/),
      'expected the user[email] input to be type="email"'

    # ...and must NOT be a resizable multi-line textarea (the Tier-3 :text-column regression).
    expect(body).not_to match(/<textarea[^>]*\bname="user\[email\]"/),
      'the user[email] field regressed to a <textarea> — check config/initializers/simple_form.rb input_mappings'
  end
end
