Rails.application.routes.draw do

  root 'organizations#index'

  # Phase 5(e) AC-2(j) access recertification report (admin-only; see AccessReviewsController).
  get 'admin/access_review', to: 'access_reviews#index', as: :access_review

  devise_for :users, controllers: { registrations: 'registrations', sessions: 'sessions', passwords: 'passwords' }

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

  get '/dashboards'     => 'dashboards#index'

  get '/quantitative_data' => 'clients#quantitative_case'

  # Google Calendar sync (re-added on upgrade/rails-7.1; see REMOVED-FEATURES.md).
  get '/redirect'      => 'calendars#redirect', as: 'redirect'
  get '/callback'      => 'calendars#callback', as: 'callback'
  get '/calendar/sync' => 'calendars#sync'
  resources :calendars

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

  resources :quantitative_cases do
    get 'version' => 'quantitative_cases#version'
  end

  resources :referral_sources, except: [:show] do
    get 'version' => 'referral_sources#version'
  end

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

  resources :program_streams do
    get :preview, on: :collection
  end

  resources :changelogs do
    get 'version' => 'changelogs#version'
  end

  get '/data_trackers' => 'data_trackers#index'

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

  resources :tasks, only: :index

  resources :clients do
    collection do
      get :advanced_search
    end

    resources :client_enrollments do
      get :report, on: :collection
      resources :client_enrollment_trackings do
        get :report, on: :collection
      end
      resources :leave_programs
    end

    resources :client_enrolled_programs do
      get :report, on: :collection
      resources :client_enrolled_program_trackings do
        get :report, on: :collection
      end
      resources :leave_enrolled_programs
    end

    resources :custom_field_properties
    # resources :government_reports
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

    resources :calendars do
      get :find_event, on: :collection
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
      end
    end
  end

  resources :client_advanced_searches, only: :index
  resources :papertrail_queries, only: [:index]
end
