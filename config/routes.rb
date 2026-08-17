Rails.application.routes.draw do

  root 'organizations#index'

  # Phase 5(e) AC-2(j) access recertification report (admin-only; see AccessReviewsController).
  get 'admin/access_review', to: 'access_reviews#index', as: :access_review

  # Phase 5 capstone — ADMIN FLAG-CONTROL-ROOM (NIST AC-3 / CM-5). Ordinary in-tenant admin route (so
  # TenantBoundary sees expected == current); singleton-per-tenant, so a GET show + PATCH update (no :id).
  get   'admin/enforcement_settings', to: 'enforcement_settings#show',   as: :enforcement_settings
  patch 'admin/enforcement_settings', to: 'enforcement_settings#update'

  # Phase 6 (POAM-SC28-UPLOADS) — the ONE authorized serve path for CarrierWave uploads now that
  # UploadsStaticGuard denies all raw /uploads/** (except the public org logo). Whitelist-constrained;
  # ?version=thumb serves the image thumbnail inline (screening-question <img> tags).
  get 'downloads/:record_type/:record_id/:mount(/:index)',
      to: 'downloads#show', as: :authorized_download,
      constraints: { record_type: /attachment|custom_field_property|case_note_domain_group|form_builder_attachment/,
                     record_id: /\d+/, mount: /file|image|attachments/, index: /\d+/ }

  # password_expired -> the app's thin PasswordExpiredController (< Devise::PasswordExpiredController) so it
  # matches the other custom devise controllers here: skip_authorization_check satisfies the Phase-5.6
  # coverage guard the same way sessions/registrations/passwords do. The route auto-emits once
  # :password_expirable is on the User model; this maps it to the app subclass.
  devise_for :users, controllers: { registrations: 'registrations', sessions: 'sessions', passwords: 'passwords', password_expired: 'password_expired' }

  # Second-factor (TOTP / recovery code) step of the two-stage login (FedRAMP IA-2(1)). Reachable only
  # mid-login, after a correct password for an MFA-enabled account (see SessionsController#create).
  # Wrapped in devise_scope so Devise can resolve the :user mapping for these SessionsController actions
  # (without it, Devise raises ActionNotFound -> 404 on the custom paths).
  devise_scope :user do
    get  'users/two_factor', to: 'sessions#two_factor_challenge', as: :two_factor_challenge
    post 'users/two_factor', to: 'sessions#verify_otp',           as: :verify_two_factor

    # Passwordless PASSKEY (WebAuthn) login ceremony — FedRAMP IA-2. An ADDITIVE, parallel sign-in
    # path; the assertion is verified in SessionsController#passkey_callback which then signs the user
    # in. In devise_scope so Devise resolves the :user mapping for these SessionsController actions.
    post 'users/passkey/options',  to: 'sessions#passkey_options',  as: :passkey_login_options
    post 'users/passkey/callback', to: 'sessions#passkey_callback', as: :passkey_login_callback
  end

  # Self-service TOTP MFA enrollment (FedRAMP IA-2(1)).
  resource :two_factor_settings, only: [:show, :create, :destroy]
  post 'two_factor_settings/backup_codes', to: 'two_factor_settings#regenerate_backup_codes',
       as: :regenerate_two_factor_backup_codes

  # Self-service passkey management + the logged-in REGISTRATION ceremony (FedRAMP IA-2). Distinct
  # from the login ceremony above. #show lists/manages; /passkeys/options issues creation options;
  # POST /passkeys verifies the attestation; DELETE removes a credential.
  resource :passkeys, only: [:show, :create], controller: 'passkeys'
  post   'passkeys/options',  to: 'passkeys#create_options', as: :passkey_registration_options
  delete 'passkeys/:id',      to: 'passkeys#destroy',        as: :passkey

  get '/robots.txt' => 'organizations#robots'

  %w(404 500).each do |code|
    match "/#{code}", to: 'errors#show', code: code, via: :all
  end

  # CSP violation report collector (POAM-017f). Browser-initiated POST (application/csp-report),
  # sent WITHOUT credentials or a CSRF token by design — auth/CSRF/authorization are skipped in
  # the controller; abuse is bounded by the rack_attack throttle + an 8 KB body cap.
  post 'csp_reports', to: 'csp_reports#create'

  get '/dashboards'     => 'dashboards#index'

  get '/quantitative_data' => 'clients#quantitative_case'

  # Data-task batch (2026-07): the calendar page (task-native feed lives under /api).
  # The legacy Google push routes (redirect/callback/sync) retired with the calendars
  # table — see REMOVED-FEATURES.md; C5 rebuilds push with its own routes.
  resources :calendars, only: [:index] do
    # C5 rebuilt Google push — connect/callback/disconnect for current_user only
    collection do
      get :google_auth
      get :google_callback
      delete :google_disconnect
    end
  end

  # Schools batch SCH1 — the browsable front for kind=school agencies.
  # S1: LOCKED to the youth flavor. The constraint is a lambda evaluated per
  # request, so a resettlement box has no school routes AT ALL (not merely a
  # hidden sidebar entry) — and specs can stub config.x.flavor to exercise them.
  constraints(->(_request) { Rails.application.config.x.flavor == 'youth' }) do
    resources :schools, only: [:index, :show, :create, :destroy] do
      member do
        get 'roster'
        get 'cohorts'
        get 'report_cards'
        get 'report_cards/new' => 'schools#new_report_cards', as: :new_report_cards
        post 'report_cards' => 'schools#create_report_cards'
        get 'roll_call'
        post 'roll_call' => 'schools#create_roll_call'
        get 'cohorts/:program_stream_id' => 'schools#cohort', as: :cohort
      end
    end
    # Sites — program-delivery locations (kind=site agencies), distinct from Schools.
    # `show` is the delivery-location page (programs hosted + youth served + campus link).
    resources :sites, only: %i[index show create update destroy]
  end
  resources :agencies, except: [:show] do
    get 'version' => 'agencies#version'
  end

  scope 'admin' do
    resources :users do
      resources :custom_field_properties
      get 'version' => 'users#version'
      get 'disable' => 'users#disable'
    end
  end

  resources :quantitative_types do
    get 'version' => 'quantitative_types#version'
  end

  # D3: the CRUD half of quantitative_cases was dead (controller has only #version —
  # values are managed inline through the type modal); changelog links survive.
  resources :quantitative_cases, only: [] do
    get 'version' => 'quantitative_cases#version'
  end

  resources :referral_sources, except: [:show] do
    get 'version' => 'referral_sources#version'
  end

  # PR 4 — the org-wide "referrals OUT" manage list (read-only roll-up across caseloads;
  # creation/edit live on the client hub via Client::ReferralsController).
  resources :referrals, only: [:index]

  resources :domain_groups, except: [:show] do
    get 'version' => 'domain_groups#version'
  end

  resources :domains, except: [:show] do
    get 'version' => 'domains#version'
  end

  resources :provinces, except: [:show] do
    get 'version' => 'provinces#version'
  end

  resources :departments, except: [:show] do
    get 'version' => 'departments#version'
  end

  resources :donors, except: [:show] do
    get 'version' => 'donors#version'
  end

  # Investor UX round (2026-07): the URL says /programs (the UI has said "Programs" since the
  # round-3 vocabulary sweep; ProgramStream stays the internal name — helpers unchanged).
  resources :program_streams, path: 'programs' do
    get :preview, on: :collection
    get :info, on: :member # read-only Program Information page (vs. the config-style show)
  end
  get '/program_streams', to: redirect('/programs')

  resources :changelogs do
    get 'version' => 'changelogs#version'
  end

  get '/data_trackers' => 'data_trackers#index'

  # Investor UX round (2026-07): the Reports landing page (charts moved off clients#index).
  # Reports batch (2026-08): :show runs a registry report — the :id is the flavor
  # registry slug, not a record id.
  resources :reports, only: [:index, :show], constraints: { id: /[a-z0-9\-]+/ }

  namespace :able_screens, path: '/' do
    namespace :question_submissions, path: '/' do
      resources :stages
      resources :able_screening_questions, except: [:index, :show]
    end

    namespace :answer_submissions do
      resources :clients do
        get 'able_screening_answers/new', to: 'able_screening_answers#new'
        post 'able_screening_answers/create', to: 'able_screening_answers#create'
      end
    end
  end

  resources :materials, except: [:show] do
    get 'version' => 'materials#version'
  end

  resources :locations, except: [:show] do
    get 'version' => 'locations#version'
  end

  resources :progress_note_types, except: [:show] do
    get 'version' => 'progress_note_types#version'
  end

  resources :interventions, except: [:show] do
    get 'version' => 'interventions#version'
  end

  resources :tasks, only: :index do
    member do
      patch :reschedule # calendar drag/drop + resize (JSON only)
    end
  end

  resources :clients do
    collection do
      get :advanced_search
    end

    resources :client_enrollments do
      # kept as a 301 to the Programs tab's pane deep link (investor UX round, 2026-07)
      get :report, on: :collection
      resources :client_enrollment_trackings
      resources :leave_programs
    end

    resources :custom_field_properties
    # UX round 3 (A1) — the merged Forms partition page (filled + available custom forms).
    resources :forms, only: [:index]
    resources :assessments do
      # Phase 5.3 — authenticated, sensitivity-gated attachment download (replaces the guessable
      # static /uploads/assessment_domain/... path as the link target).
      get 'assessment_domains/:assessment_domain_id/attachments/:index',
          to: 'assessments#download_attachment', as: :download_attachment, on: :member
    end
    resources :case_notes
    resources :cases do
      scope module: 'case' do
        resources :quarterly_reports, only: [:index, :show]
      end
    end
    scope module: 'client' do
      resources :tasks
      # PR 4 — referrals OUT: the per-client hub section (Client::ReferralsController).
      resources :referrals
    end
    # resources :surveys

    resources :progress_notes do
      get 'version' => 'progress_notes#version'
    end

    get 'version' => 'clients#version'
  end

  resources :attachments, only: [:index] do
    collection do
      get 'delete' => 'attachments#delete'
    end
  end

  resources :families do
    resources :custom_field_properties
    # UX round 3 (B1) — the family hub's merged Forms partition page.
    resources :forms, only: [:index]
    # UX round 3 (B2) — household-level notes (the hub's Notes tab).
    resources :family_notes
    # UX round 3 (B3) — household alerts. Resolve-not-delete: no show/destroy routes.
    resources :family_alerts, except: %i[show destroy] do
      patch :resolve, on: :member
    end
    get 'version' => 'families#version'
  end

  resources :partners do
    resources :custom_field_properties
    get 'version' => 'partners#version'
  end

  resources :notifications, only: [:index]

  # NOTE: the versioned mobile API (namespace :v1) + devise_token_auth were removed on
  # branch upgrade/rails-7.1 (see REMOVED-FEATURES.md). These remaining /api endpoints are
  # AJAX helpers the WEB UI depends on (duplicate detection, dynamic form fields, advanced
  # search filters, query builder) — keep them.
  namespace :api do
    resources :form_builder_attachments, only: :destroy

    resources :calendars, only: [] do
      get :find_event, on: :collection
      # owner flip (2026-07-31): person first, then their programs (was program -> people)
      get :client_programs, on: :collection
    end

    resources :clients do
      get :compare, on: :collection
    end
    resources :custom_fields do
      get :fetch_custom_fields, on: :collection
      get :fields
    end
    resources :client_advanced_searches, only: [] do
      collection do
        get :get_custom_field
        get :get_basic_field
        get :get_enrollment_field
        get :get_tracking_field
        get :get_exit_program_field
      end
    end
    resources :program_stream_add_rule, only: [] do
      collection do
        get :get_fields
      end
    end

    resources :program_streams, only: [] do
      get :enrollment_fields
      get :exit_program_fields
      get :tracking_fields
    end
  end


  scope '', module: 'form_builder' do
    resources :custom_fields do
      collection do
        get 'search' => 'custom_fields#search', as: :search
        get 'preview' => 'custom_fields#show', as: 'preview'
        # D5: REAL preview — renders the actual shared/fields data-entry partials from
        # the builder's draft JSON (POST: the draft is too big for a query string)
        post 'preview_draft' => 'custom_fields#preview_draft', as: 'preview_draft'
      end
    end
  end

  resources :client_advanced_searches, only: :index
  resources :papertrail_queries, only: [:index]

  # Phase 5.4 — DEDICATED break-glass elevation endpoint (NIST AC-3 / AC-6(2) / AU-2).
  # NOT a member action of clients (bypass E): a top-level POST so it is never subject to
  # ClientsController's load_and_authorize_resource. The controller does its own readability
  # gate (accessible_by) and authorizes `can :create, BreakGlassGrant`.
  resources :break_glass_grants, only: [:create]
end
