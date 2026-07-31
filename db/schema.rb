# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_30_000007) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "shared_extensions.hstore"
  enable_extension "shared_extensions.uuid-ossp"

  create_table "able_screening_questions", id: :serial, force: :cascade do |t|
    t.boolean "alert_manager"
    t.datetime "created_at", precision: nil, null: false
    t.string "mode"
    t.string "question"
    t.integer "question_group_id"
    t.integer "stage_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["question_group_id"], name: "index_able_screening_questions_on_question_group_id"
    t.index ["stage_id"], name: "index_able_screening_questions_on_stage_id"
  end

  create_table "agencies", id: :serial, force: :cascade do |t|
    t.integer "agencies_clients_count", default: 0
    t.datetime "created_at", precision: nil
    t.text "description", default: ""
    t.string "name", default: ""
    t.datetime "updated_at", precision: nil
  end

  create_table "agency_clients", id: :serial, force: :cascade do |t|
    t.integer "agency_id"
    t.integer "client_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "agency_program_streams", force: :cascade do |t|
    t.integer "agency_id", null: false
    t.datetime "created_at", null: false
    t.integer "program_stream_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agency_id", "program_stream_id"], name: "idx_agency_program_streams_pair", unique: true
    t.index ["program_stream_id"], name: "idx_agency_program_streams_ps"
  end

  create_table "answers", id: :serial, force: :cascade do |t|
    t.integer "able_screening_question_id"
    t.integer "client_id"
    t.datetime "created_at", precision: nil, null: false
    t.string "description"
    t.string "question_type", default: ""
    t.datetime "updated_at", precision: nil, null: false
    t.index ["able_screening_question_id"], name: "index_answers_on_able_screening_question_id"
    t.index ["client_id"], name: "index_answers_on_client_id"
  end

  create_table "assessment_domains", id: :serial, force: :cascade do |t|
    t.integer "assessment_id"
    t.string "attachments", default: [], array: true
    t.datetime "created_at", precision: nil
    t.integer "domain_id"
    t.text "goal", default: ""
    t.text "note", default: ""
    t.integer "previous_score"
    t.text "reason", default: ""
    t.integer "score"
    t.datetime "updated_at", precision: nil
  end

  create_table "assessment_domains_progress_notes", id: :serial, force: :cascade do |t|
    t.integer "assessment_domain_id"
    t.datetime "created_at", precision: nil
    t.integer "progress_note_id"
    t.datetime "updated_at", precision: nil
    t.index ["assessment_domain_id"], name: "index_assessment_domains_progress_notes_on_assessment_domain_id"
    t.index ["progress_note_id"], name: "index_assessment_domains_progress_notes_on_progress_note_id"
  end

  create_table "assessments", id: :serial, force: :cascade do |t|
    t.integer "client_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.index ["client_id"], name: "index_assessments_on_client_id"
  end

  create_table "attachments", id: :serial, force: :cascade do |t|
    t.integer "able_screening_question_id"
    t.datetime "created_at", precision: nil, null: false
    t.string "file", default: ""
    t.string "image"
    t.integer "progress_note_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["able_screening_question_id"], name: "index_attachments_on_able_screening_question_id"
    t.index ["progress_note_id"], name: "index_attachments_on_progress_note_id"
  end

  create_table "break_glass_grants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "custom_field_id"
    t.integer "custom_formable_id", null: false
    t.string "custom_formable_type", null: false
    t.datetime "expires_at", null: false
    t.text "reason", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["expires_at"], name: "idx_bgg_expires_at"
    t.index ["user_id", "custom_formable_type", "custom_formable_id", "expires_at"], name: "idx_bgg_user_record_active"
  end

  create_table "case_contracts", id: :serial, force: :cascade do |t|
    t.integer "case_id"
    t.datetime "created_at", precision: nil
    t.date "signed_on"
    t.datetime "updated_at", precision: nil
    t.index ["case_id"], name: "index_case_contracts_on_case_id"
  end

  create_table "case_note_domain_groups", id: :serial, force: :cascade do |t|
    t.string "attachments", default: [], array: true
    t.integer "case_note_id"
    t.datetime "created_at", precision: nil
    t.integer "domain_group_id"
    t.text "note", default: ""
    t.datetime "updated_at", precision: nil
  end

  create_table "case_notes", id: :serial, force: :cascade do |t|
    t.integer "assessment_id"
    t.string "attendee", default: ""
    t.integer "client_id"
    t.datetime "created_at", precision: nil
    t.date "meeting_date"
    t.datetime "updated_at", precision: nil
    t.index ["client_id"], name: "index_case_notes_on_client_id"
  end

  create_table "case_worker_clients", id: :serial, force: :cascade do |t|
    t.integer "client_id"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "user_id"
    t.index ["client_id"], name: "index_case_worker_clients_on_client_id"
    t.index ["user_id"], name: "index_case_worker_clients_on_user_id"
  end

  create_table "case_worker_tasks", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.integer "task_id"
    t.datetime "updated_at", precision: nil
    t.integer "user_id"
    t.index ["task_id"], name: "index_case_worker_tasks_on_task_id"
    t.index ["user_id"], name: "index_case_worker_tasks_on_user_id"
  end

  create_table "cases", id: :serial, force: :cascade do |t|
    t.string "carer_address", default: ""
    t.string "carer_names", default: ""
    t.string "carer_phone_number", default: ""
    t.date "case_conference_date"
    t.float "case_length"
    t.text "case_type", default: "EC"
    t.integer "client_id"
    t.datetime "created_at", precision: nil
    t.boolean "current", default: true
    t.date "exit_date"
    t.text "exit_note", default: ""
    t.boolean "exited", default: false
    t.boolean "exited_from_cif", default: false
    t.integer "family_id"
    t.boolean "family_preservation", default: false
    t.date "initial_assessment_date"
    t.integer "partner_id"
    t.date "placement_date"
    t.integer "province_id"
    t.date "start_date"
    t.string "status", default: ""
    t.float "support_amount", default: 0.0
    t.text "support_note", default: ""
    t.float "time_in_care"
    t.datetime "updated_at", precision: nil
    t.integer "user_id"
  end

  create_table "changelog_types", id: :serial, force: :cascade do |t|
    t.string "change_type", default: ""
    t.integer "changelog_id"
    t.datetime "created_at", precision: nil
    t.string "description", default: ""
    t.datetime "updated_at", precision: nil
    t.index ["changelog_id"], name: "index_changelog_types_on_changelog_id"
  end

  create_table "changelogs", id: :serial, force: :cascade do |t|
    t.string "change_version", default: ""
    t.datetime "created_at", precision: nil
    t.string "description", default: ""
    t.datetime "updated_at", precision: nil
    t.integer "user_id"
    t.index ["user_id"], name: "index_changelogs_on_user_id"
  end

  create_table "client_enrollment_search_entries", force: :cascade do |t|
    t.integer "client_enrollment_id", null: false
    t.datetime "created_at", null: false
    t.text "field_label", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["client_enrollment_id", "field_label"], name: "idx_ce_se_owner_label"
    t.index ["field_label"], name: "idx_ce_se_label"
    t.index ["value"], name: "idx_ce_se_value_hash", using: :hash
  end

  create_table "client_enrollment_tracking_search_entries", force: :cascade do |t|
    t.integer "client_enrollment_tracking_id", null: false
    t.datetime "created_at", null: false
    t.text "field_label", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["client_enrollment_tracking_id", "field_label"], name: "idx_cet_se_owner_label"
    t.index ["field_label"], name: "idx_cet_se_label"
    t.index ["value"], name: "idx_cet_se_value_hash", using: :hash
  end

  create_table "client_enrollment_trackings", id: :serial, force: :cascade do |t|
    t.integer "client_enrollment_id"
    t.datetime "created_at", precision: nil, null: false
    t.text "properties", default: "{}"
    t.integer "tracking_id"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["client_enrollment_id"], name: "index_client_enrollment_trackings_on_client_enrollment_id"
  end

  create_table "client_enrollments", id: :serial, force: :cascade do |t|
    t.integer "client_id"
    t.datetime "created_at", precision: nil, null: false
    t.date "enrollment_date"
    t.integer "program_stream_id"
    t.text "properties", default: "{}"
    t.string "status", default: "Active"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["client_id"], name: "index_client_enrollments_on_client_id"
    t.index ["program_stream_id"], name: "index_client_enrollments_on_program_stream_id"
  end

  create_table "client_quantitative_cases", id: :serial, force: :cascade do |t|
    t.integer "client_id"
    t.datetime "created_at", precision: nil
    t.integer "quantitative_case_id"
    t.datetime "updated_at", precision: nil
    t.index ["client_id", "quantitative_case_id"], name: "idx_client_quantitative_cases_pair", unique: true
    t.index ["quantitative_case_id"], name: "idx_client_quantitative_cases_case"
  end

  create_table "clients", id: :serial, force: :cascade do |t|
    t.boolean "able", default: false
    t.string "able_state", default: ""
    t.date "accepted_date"
    t.integer "assessments_count", default: 0
    t.text "background", default: ""
    t.integer "birth_province_id"
    t.string "code", default: ""
    t.text "commune", default: ""
    t.boolean "completed", default: false
    t.datetime "created_at", precision: nil
    t.text "current_address", default: ""
    t.date "date_of_birth"
    t.text "district", default: ""
    t.integer "donor_id"
    t.text "email"
    t.date "exit_date"
    t.text "exit_note", default: ""
    t.text "family_name", default: ""
    t.date "follow_up_date"
    t.integer "followed_up_by_id"
    t.string "gender"
    t.text "given_name", default: ""
    t.integer "grade", default: 0
    t.boolean "has_been_in_government_care", default: false
    t.boolean "has_been_in_orphanage", default: false
    t.text "house_number", default: ""
    t.integer "id_poor", default: 0
    t.date "initial_referral_date"
    t.boolean "is_receiving_additional_benefits", default: false
    t.string "kid_id", default: ""
    t.text "live_with", default: ""
    t.text "local_family_name", default: ""
    t.text "local_given_name", default: ""
    t.boolean "notify_consent", default: false, null: false
    t.text "original_family_name"
    t.text "original_given_name"
    t.text "original_local_family_name"
    t.text "original_local_given_name"
    t.integer "province_id"
    t.text "reason_for_referral", default: ""
    t.integer "received_by_id"
    t.string "referral_phone", default: ""
    t.integer "referral_source_id"
    t.text "rejected_note", default: ""
    t.text "relevant_referral_information", default: ""
    t.integer "rice_support", default: 0
    t.string "school_grade", default: ""
    t.text "school_name", default: ""
    t.string "slug"
    t.string "state", default: ""
    t.string "status", default: "Referred"
    t.text "street_number", default: ""
    t.datetime "updated_at", precision: nil
    t.integer "user_id"
    t.text "village", default: ""
    t.index ["donor_id"], name: "index_clients_on_donor_id"
    t.index ["slug"], name: "index_clients_on_slug", unique: true
  end

  create_table "clients_quantitative_cases", id: :serial, force: :cascade do |t|
    t.integer "client_id"
    t.datetime "created_at", precision: nil
    t.integer "quantitative_case_id"
    t.datetime "updated_at", precision: nil
  end

  create_table "custom_field_properties", id: :serial, force: :cascade do |t|
    t.jsonb "attachments"
    t.datetime "created_at", precision: nil, null: false
    t.integer "custom_field_id"
    t.integer "custom_formable_id"
    t.string "custom_formable_type"
    t.text "properties", default: "{}"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["custom_field_id"], name: "index_custom_field_properties_on_custom_field_id"
  end

  create_table "custom_field_property_search_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "custom_field_property_id", null: false
    t.text "field_label", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["custom_field_property_id", "field_label"], name: "idx_cfp_se_owner_label"
    t.index ["field_label"], name: "idx_cfp_se_label"
    t.index ["value"], name: "idx_cfp_se_value_hash", using: :hash
  end

  create_table "custom_fields", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "entity_type", default: ""
    t.jsonb "fields"
    t.string "form_title", default: ""
    t.string "frequency", default: ""
    t.string "ngo_name", default: ""
    t.text "properties", default: ""
    t.string "sensitivity", default: "standard", null: false
    t.integer "time_of_frequency", default: 0
    t.datetime "updated_at", precision: nil, null: false
    t.index ["sensitivity"], name: "index_custom_fields_on_sensitivity"
  end

  create_table "departments", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.text "description", default: ""
    t.string "name", default: ""
    t.datetime "updated_at", precision: nil
    t.integer "users_count", default: 0
  end

  create_table "domain_groups", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.text "description", default: ""
    t.integer "domains_count", default: 0
    t.string "name", default: ""
    t.datetime "updated_at", precision: nil
  end

  create_table "domain_program_streams", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "domain_id"
    t.integer "program_stream_id"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "domains", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.text "description", default: ""
    t.integer "domain_group_id"
    t.string "identity", default: ""
    t.string "name", default: ""
    t.string "score_1_color", default: "danger"
    t.string "score_2_color", default: "warning"
    t.string "score_3_color", default: "info"
    t.string "score_4_color", default: "primary"
    t.string "sensitivity", default: "standard", null: false
    t.integer "tasks_count", default: 0
    t.datetime "updated_at", precision: nil
    t.index ["domain_group_id"], name: "index_domains_on_domain_group_id"
    t.index ["sensitivity"], name: "index_domains_on_sensitivity"
  end

  create_table "donors", id: :serial, force: :cascade do |t|
    t.string "code", default: ""
    t.datetime "created_at", precision: nil, null: false
    t.text "description", default: ""
    t.string "name", default: ""
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "enforcement_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enforce_authorization"
    t.boolean "enforce_least_privilege"
    t.boolean "enforce_tenant_boundary"
    t.integer "idle_timeout_minutes"
    t.integer "inactive_disable_days"
    t.integer "lockout_max_attempts"
    t.integer "lockout_unlock_in_minutes"
    t.integer "password_max_age_days"
    t.boolean "require_mfa"
    t.datetime "updated_at", null: false
    t.integer "updated_by_id"
  end

  create_table "families", id: :serial, force: :cascade do |t|
    t.text "address", default: ""
    t.text "caregiver_information", default: ""
    t.text "case_history", default: ""
    t.integer "cases_count", default: 0
    t.string "code"
    t.date "contract_date"
    t.datetime "created_at", precision: nil
    t.boolean "dependable_income", default: false
    t.string "family_type", default: "kinship"
    t.integer "female_adult_count", default: 0
    t.integer "female_children_count", default: 0
    t.float "household_income", default: 0.0
    t.integer "male_adult_count", default: 0
    t.integer "male_children_count", default: 0
    t.string "name", default: ""
    t.integer "province_id"
    t.integer "significant_family_member_count", default: 1
    t.datetime "updated_at", precision: nil
  end

  create_table "family_alerts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.bigint "family_id", null: false
    t.datetime "resolved_at"
    t.bigint "resolved_by_id"
    t.string "severity", default: "caution", null: false
    t.text "title"
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_family_alerts_on_created_by_id"
    t.index ["family_id", "resolved_at"], name: "index_family_alerts_on_family_id_and_resolved_at"
    t.index ["family_id"], name: "index_family_alerts_on_family_id"
    t.index ["resolved_by_id"], name: "index_family_alerts_on_resolved_by_id"
  end

  create_table "family_notes", force: :cascade do |t|
    t.string "attendee"
    t.datetime "created_at", null: false
    t.bigint "family_id", null: false
    t.date "meeting_date", null: false
    t.text "note"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["family_id"], name: "index_family_notes_on_family_id"
    t.index ["user_id"], name: "index_family_notes_on_user_id"
  end

  create_table "form_builder_attachments", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.jsonb "file", default: []
    t.integer "form_buildable_id"
    t.string "form_buildable_type"
    t.string "name", default: ""
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "friendly_id_slugs", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.string "scope"
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_id"
    t.index ["sluggable_type"], name: "index_friendly_id_slugs_on_sluggable_type"
  end

  create_table "google_task_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "google_event_id", null: false
    t.integer "task_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["task_id", "user_id"], name: "idx_google_task_events_task_user", unique: true
    t.index ["user_id"], name: "idx_google_task_events_user"
  end

  create_table "government_reports", id: :serial, force: :cascade do |t|
    t.date "agreed_date"
    t.boolean "anonymous", default: false
    t.text "anonymous_description", default: ""
    t.string "capital", default: ""
    t.string "carer_capital", default: ""
    t.string "carer_city", default: ""
    t.string "carer_commune", default: ""
    t.string "carer_house_number", default: ""
    t.string "carer_name", default: ""
    t.string "carer_phone_number", default: ""
    t.string "carer_street_number", default: ""
    t.string "carer_village", default: ""
    t.date "case_information_date"
    t.string "city", default: ""
    t.string "client_code", default: ""
    t.string "client_contact", default: ""
    t.date "client_date_of_birth"
    t.string "client_gender", default: ""
    t.integer "client_id"
    t.boolean "client_living_with_guardian", default: false
    t.string "client_name", default: ""
    t.string "code", default: ""
    t.string "commune", default: ""
    t.datetime "created_at", precision: nil
    t.date "done_date"
    t.string "education", default: ""
    t.text "education_need", default: ""
    t.text "education_plan", default: ""
    t.text "emotional_health_need", default: ""
    t.text "emotional_health_plan", default: ""
    t.text "family_communication_need", default: ""
    t.text "family_communication_plan", default: ""
    t.boolean "first_mission", default: false
    t.string "found_client_at", default: ""
    t.string "found_client_village", default: ""
    t.boolean "fourth_mission", default: false
    t.string "initial_capital", default: ""
    t.string "initial_city", default: ""
    t.string "initial_commune", default: ""
    t.date "initial_date"
    t.boolean "mission_obtainable", default: false
    t.string "organisation_name", default: ""
    t.string "organisation_phone_number", default: ""
    t.text "physical_health_need", default: ""
    t.text "physical_health_plan", default: ""
    t.text "present_education", default: ""
    t.text "present_emotional_health", default: ""
    t.text "present_family_communication", default: ""
    t.text "present_physical_health", default: ""
    t.text "present_society_communication", default: ""
    t.text "present_supplies", default: ""
    t.string "referral_name", default: ""
    t.string "referral_position", default: ""
    t.boolean "second_mission", default: false
    t.text "society_communication_need", default: ""
    t.text "society_communication_plan", default: ""
    t.text "supplies_need", default: ""
    t.text "supplies_plan", default: ""
    t.boolean "third_mission", default: false
    t.datetime "updated_at", precision: nil
  end

  create_table "interventions", id: :serial, force: :cascade do |t|
    t.string "action", default: ""
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
  end

  create_table "interventions_progress_notes", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.integer "intervention_id"
    t.integer "progress_note_id"
    t.datetime "updated_at", precision: nil
    t.index ["intervention_id"], name: "index_interventions_progress_notes_on_intervention_id"
    t.index ["progress_note_id"], name: "index_interventions_progress_notes_on_progress_note_id"
  end

  create_table "leave_program_search_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "field_label", null: false
    t.integer "leave_program_id", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["field_label"], name: "idx_lp_se_label"
    t.index ["leave_program_id", "field_label"], name: "idx_lp_se_owner_label"
    t.index ["value"], name: "idx_lp_se_value_hash", using: :hash
  end

  create_table "leave_programs", id: :serial, force: :cascade do |t|
    t.integer "client_enrollment_id"
    t.datetime "created_at", precision: nil, null: false
    t.date "exit_date"
    t.integer "program_stream_id"
    t.text "properties", default: "{}"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["client_enrollment_id"], name: "index_leave_programs_on_client_enrollment_id"
  end

  create_table "locations", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.string "name", default: ""
    t.integer "order_option", default: 0
    t.datetime "updated_at", precision: nil
  end

  create_table "materials", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.string "status", default: ""
    t.datetime "updated_at", precision: nil
  end

  create_table "old_passwords", force: :cascade do |t|
    t.datetime "created_at"
    t.string "encrypted_password", null: false
    t.bigint "password_archivable_id", null: false
    t.string "password_archivable_type", null: false
    t.string "password_salt"
    t.index ["password_archivable_type", "password_archivable_id"], name: "index_old_passwords_on_password_archivable"
  end

  create_table "organizations", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.boolean "fcf_ngo", default: false
    t.string "full_name"
    t.string "logo"
    t.string "short_name"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "partners", id: :serial, force: :cascade do |t|
    t.text "address", default: ""
    t.string "affiliation", default: ""
    t.text "background", default: ""
    t.integer "cases_count", default: 0
    t.string "contact_person_email", default: ""
    t.string "contact_person_mobile", default: ""
    t.string "contact_person_name", default: ""
    t.datetime "created_at", precision: nil
    t.string "engagement", default: ""
    t.string "name", default: ""
    t.string "organisation_type", default: ""
    t.integer "province_id"
    t.date "start_date"
    t.datetime "updated_at", precision: nil
  end

  create_table "program_streams", id: :serial, force: :cascade do |t|
    t.boolean "completed", default: false
    t.datetime "created_at", precision: nil, null: false
    t.text "description"
    t.jsonb "enrollment", default: {}
    t.jsonb "exit_program", default: {}
    t.integer "mutual_dependence", default: [], array: true
    t.string "name"
    t.string "ngo_name", default: ""
    t.integer "program_exclusive", default: [], array: true
    t.integer "quantity"
    t.jsonb "rules", default: {}
    t.boolean "tracking_required", default: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "progress_note_types", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.string "note_type", default: ""
    t.datetime "updated_at", precision: nil
  end

  create_table "progress_notes", id: :serial, force: :cascade do |t|
    t.text "additional_note", default: ""
    t.integer "client_id"
    t.datetime "created_at", precision: nil
    t.date "date"
    t.integer "location_id"
    t.integer "material_id"
    t.string "other_location", default: ""
    t.integer "progress_note_type_id"
    t.text "response", default: ""
    t.datetime "updated_at", precision: nil
    t.integer "user_id"
    t.index ["client_id"], name: "index_progress_notes_on_client_id"
    t.index ["location_id"], name: "index_progress_notes_on_location_id"
    t.index ["material_id"], name: "index_progress_notes_on_material_id"
    t.index ["progress_note_type_id"], name: "index_progress_notes_on_progress_note_type_id"
    t.index ["user_id"], name: "index_progress_notes_on_user_id"
  end

  create_table "provinces", id: :serial, force: :cascade do |t|
    t.integer "cases_count", default: 0
    t.integer "clients_count", default: 0
    t.datetime "created_at", precision: nil
    t.text "description", default: ""
    t.integer "families_count", default: 0
    t.string "name", default: ""
    t.integer "partners_count", default: 0
    t.datetime "updated_at", precision: nil
    t.integer "users_count", default: 0
  end

  create_table "quantitative_cases", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.integer "quantitative_type_id"
    t.datetime "updated_at", precision: nil
    t.string "value", default: ""
    t.index ["quantitative_type_id"], name: "idx_quantitative_cases_type"
  end

  create_table "quantitative_types", id: :serial, force: :cascade do |t|
    t.boolean "allow_multiple", default: true, null: false
    t.datetime "created_at", precision: nil
    t.text "description", default: ""
    t.string "name", default: ""
    t.integer "quantitative_cases_count", default: 0
    t.datetime "updated_at", precision: nil
  end

  create_table "quarterly_reports", id: :serial, force: :cascade do |t|
    t.integer "case_id"
    t.text "child_school_attendance_or_progress", default: ""
    t.bigint "code"
    t.datetime "created_at", precision: nil, null: false
    t.text "describe_if_yes", default: ""
    t.text "describe_the_family_current_situation", default: ""
    t.text "general_appearance_of_home", default: ""
    t.text "general_health_or_appearance", default: ""
    t.text "has_the_situation_changed_from_the_previous_visit", default: ""
    t.text "how_are_they_being_misused", default: ""
    t.text "how_did_i_encourage_the_client", default: ""
    t.boolean "money_and_supplies_being_used_appropriately", default: false
    t.text "observations_of_drug_alchohol_abuse", default: ""
    t.text "spiritual_developments_with_the_child_or_family", default: ""
    t.integer "staff_id"
    t.datetime "updated_at", precision: nil, null: false
    t.date "visit_date"
    t.text "what_future_teachings_or_trainings_could_help_the_client", default: ""
    t.text "what_is_my_plan_for_the_next_visit_to_the_client", default: ""
    t.index ["case_id"], name: "index_quarterly_reports_on_case_id"
  end

  create_table "question_groups", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "name"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "referral_sources", id: :serial, force: :cascade do |t|
    t.integer "clients_count", default: 0
    t.datetime "created_at", precision: nil
    t.text "description", default: ""
    t.string "name", default: ""
    t.datetime "updated_at", precision: nil
  end

  create_table "stages", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.float "from_age"
    t.float "to_age"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "surveys", id: :serial, force: :cascade do |t|
    t.integer "care_score"
    t.integer "client_id"
    t.datetime "created_at", precision: nil
    t.integer "difficulty_help_score"
    t.integer "family_need_score"
    t.integer "getting_in_touch_score"
    t.integer "listening_score"
    t.integer "problem_solving_score"
    t.integer "support_score"
    t.integer "trust_score"
    t.datetime "updated_at", precision: nil
    t.integer "user_id"
    t.index ["client_id"], name: "index_surveys_on_client_id"
  end

  create_table "tasks", id: :serial, force: :cascade do |t|
    t.integer "case_note_domain_group_id"
    t.integer "client_id"
    t.boolean "completed", default: false
    t.date "completion_date"
    t.datetime "created_at", precision: nil
    t.integer "domain_id"
    t.integer "duration_minutes"
    t.string "name", default: ""
    t.time "start_time"
    t.datetime "updated_at", precision: nil
    t.integer "user_id"
    t.index ["client_id"], name: "index_tasks_on_client_id"
    t.index ["completion_date"], name: "idx_tasks_completion_date"
  end

  create_table "thredded_categories", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "description", limit: 255
    t.integer "messageboard_id", null: false
    t.string "name", limit: 191, null: false
    t.string "slug", limit: 191, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index "lower((name)::text) text_pattern_ops", name: "thredded_categories_name_ci"
    t.index ["messageboard_id", "slug"], name: "index_thredded_categories_on_messageboard_id_and_slug", unique: true
    t.index ["messageboard_id"], name: "index_thredded_categories_on_messageboard_id"
  end

  create_table "thredded_messageboard_groups", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "name"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "thredded_messageboard_users", id: :serial, force: :cascade do |t|
    t.datetime "last_seen_at", precision: nil, null: false
    t.integer "thredded_messageboard_id", null: false
    t.integer "thredded_user_detail_id", null: false
    t.index ["thredded_messageboard_id", "last_seen_at"], name: "index_thredded_messageboard_users_for_recently_active"
    t.index ["thredded_messageboard_id", "thredded_user_detail_id"], name: "index_thredded_messageboard_users_primary"
  end

  create_table "thredded_messageboards", id: :serial, force: :cascade do |t|
    t.boolean "closed", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.text "description"
    t.integer "last_topic_id"
    t.integer "messageboard_group_id"
    t.string "name", limit: 255, null: false
    t.integer "posts_count", default: 0
    t.string "slug", limit: 191
    t.integer "topics_count", default: 0
    t.datetime "updated_at", precision: nil, null: false
    t.index ["closed"], name: "index_thredded_messageboards_on_closed"
    t.index ["messageboard_group_id"], name: "index_thredded_messageboards_on_messageboard_group_id"
    t.index ["slug"], name: "index_thredded_messageboards_on_slug"
  end

  create_table "thredded_post_moderation_records", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "messageboard_id"
    t.integer "moderation_state", null: false
    t.integer "moderator_id"
    t.text "post_content"
    t.integer "post_id"
    t.integer "post_user_id"
    t.text "post_user_name"
    t.integer "previous_moderation_state", null: false
    t.index ["messageboard_id", "created_at"], name: "index_thredded_moderation_records_for_display", order: { created_at: :desc }
  end

  create_table "thredded_post_notifications", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "email", limit: 191, null: false
    t.integer "post_id", null: false
    t.string "post_type", limit: 191
    t.datetime "updated_at", precision: nil, null: false
    t.index ["post_id", "post_type"], name: "index_thredded_post_notifications_on_post"
  end

  create_table "thredded_posts", id: :serial, force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", precision: nil, null: false
    t.string "ip", limit: 255
    t.integer "messageboard_id", null: false
    t.integer "moderation_state", null: false
    t.integer "postable_id", null: false
    t.string "source", limit: 255, default: "web"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index "to_tsvector('english'::regconfig, content)", name: "thredded_posts_content_fts", using: :gist
    t.index ["messageboard_id"], name: "index_thredded_posts_on_messageboard_id"
    t.index ["moderation_state", "updated_at"], name: "index_thredded_posts_for_display"
    t.index ["postable_id"], name: "index_thredded_posts_on_postable_id_and_postable_type"
    t.index ["user_id"], name: "index_thredded_posts_on_user_id"
  end

  create_table "thredded_private_posts", id: :serial, force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", precision: nil, null: false
    t.string "ip", limit: 255
    t.integer "postable_id", null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
  end

  create_table "thredded_private_topics", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "hash_id", limit: 191, null: false
    t.integer "last_user_id"
    t.integer "posts_count", default: 0
    t.string "slug", limit: 191, null: false
    t.string "title", limit: 255, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["hash_id"], name: "index_thredded_private_topics_on_hash_id"
    t.index ["slug"], name: "index_thredded_private_topics_on_slug"
  end

  create_table "thredded_private_users", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "private_topic_id"
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index ["private_topic_id"], name: "index_thredded_private_users_on_private_topic_id"
    t.index ["user_id"], name: "index_thredded_private_users_on_user_id"
  end

  create_table "thredded_topic_categories", id: :serial, force: :cascade do |t|
    t.integer "category_id", null: false
    t.integer "topic_id", null: false
    t.index ["category_id"], name: "index_thredded_topic_categories_on_category_id"
    t.index ["topic_id"], name: "index_thredded_topic_categories_on_topic_id"
  end

  create_table "thredded_topics", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.string "hash_id", limit: 191, null: false
    t.integer "last_user_id"
    t.boolean "locked", default: false, null: false
    t.integer "messageboard_id", null: false
    t.integer "moderation_state", null: false
    t.integer "posts_count", default: 0, null: false
    t.string "slug", limit: 191, null: false
    t.boolean "sticky", default: false, null: false
    t.string "title", limit: 255, null: false
    t.string "type", limit: 191
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id"
    t.index "to_tsvector('english'::regconfig, (title)::text)", name: "thredded_topics_title_fts", using: :gist
    t.index ["hash_id"], name: "index_thredded_topics_on_hash_id"
    t.index ["messageboard_id", "slug"], name: "index_thredded_topics_on_messageboard_id_and_slug", unique: true
    t.index ["messageboard_id"], name: "index_thredded_topics_on_messageboard_id"
    t.index ["moderation_state", "sticky", "updated_at"], name: "index_thredded_topics_for_display", order: { sticky: :desc, updated_at: :desc }
    t.index ["user_id"], name: "index_thredded_topics_on_user_id"
  end

  create_table "thredded_user_details", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.datetime "last_seen_at", precision: nil
    t.datetime "latest_activity_at", precision: nil
    t.integer "moderation_state", default: 1, null: false
    t.datetime "moderation_state_changed_at", precision: nil
    t.integer "posts_count", default: 0
    t.integer "topics_count", default: 0
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id", null: false
    t.index ["latest_activity_at"], name: "index_thredded_user_details_on_latest_activity_at"
    t.index ["moderation_state", "moderation_state_changed_at"], name: "index_thredded_user_details_for_moderations", order: { moderation_state_changed_at: :desc }
    t.index ["user_id"], name: "index_thredded_user_details_on_user_id"
  end

  create_table "thredded_user_messageboard_preferences", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "messageboard_id", null: false
    t.boolean "notify_on_mention", default: true, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id", null: false
    t.index ["user_id", "messageboard_id"], name: "thredded_user_messageboard_preferences_user_id_messageboard_id", unique: true
  end

  create_table "thredded_user_preferences", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.boolean "notify_on_mention", default: true, null: false
    t.boolean "notify_on_message", default: true, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_thredded_user_preferences_on_user_id"
  end

  create_table "thredded_user_private_topic_read_states", id: :serial, force: :cascade do |t|
    t.integer "page", default: 1, null: false
    t.integer "postable_id", null: false
    t.datetime "read_at", precision: nil, null: false
    t.integer "user_id", null: false
    t.index ["user_id", "postable_id"], name: "thredded_user_private_topic_read_states_user_postable", unique: true
  end

  create_table "thredded_user_topic_follows", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.integer "reason", limit: 2
    t.integer "topic_id", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "topic_id"], name: "thredded_user_topic_follows_user_topic", unique: true
  end

  create_table "thredded_user_topic_read_states", id: :serial, force: :cascade do |t|
    t.integer "page", default: 1, null: false
    t.integer "postable_id", null: false
    t.datetime "read_at", precision: nil, null: false
    t.integer "user_id", null: false
    t.index ["user_id", "postable_id"], name: "thredded_user_topic_read_states_user_postable", unique: true
  end

  create_table "trackings", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.jsonb "fields", default: {}
    t.string "frequency", default: ""
    t.string "name", default: ""
    t.integer "program_stream_id"
    t.integer "time_of_frequency"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["name", "program_stream_id"], name: "index_trackings_on_name_and_program_stream_id", unique: true
    t.index ["program_stream_id"], name: "index_trackings_on_program_stream_id"
  end

  create_table "users", id: :serial, force: :cascade do |t|
    t.boolean "admin", default: false
    t.boolean "archived", default: false
    t.boolean "calendar_integration", default: false
    t.integer "cases_count", default: 0
    t.integer "changelogs_count", default: 0
    t.integer "clients_count", default: 0
    t.integer "consumed_timestep"
    t.datetime "created_at", precision: nil
    t.datetime "current_sign_in_at", precision: nil
    t.inet "current_sign_in_ip"
    t.date "date_of_birth"
    t.integer "department_id"
    t.boolean "disable", default: false
    t.text "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "expires_at", precision: nil
    t.integer "failed_attempts", default: 0, null: false
    t.text "first_name", default: ""
    t.text "google_refresh_token"
    t.string "job_title", default: ""
    t.text "last_name", default: ""
    t.datetime "last_sign_in_at", precision: nil
    t.inet "last_sign_in_ip"
    t.datetime "locked_at"
    t.integer "manager_id"
    t.integer "manager_ids", default: [], array: true
    t.text "mobile", default: ""
    t.integer "organization_id"
    t.string "otp_backup_codes", array: true
    t.boolean "otp_required_for_login", default: false, null: false
    t.text "otp_secret"
    t.datetime "password_changed_at"
    t.integer "pin_number"
    t.boolean "program_warning", default: false
    t.string "provider", default: "email", null: false
    t.integer "province_id"
    t.datetime "remember_created_at", precision: nil
    t.datetime "reset_password_sent_at", precision: nil
    t.string "reset_password_token"
    t.string "roles", default: "case worker"
    t.integer "sign_in_count", default: 0, null: false
    t.boolean "staff_performance_notification", default: true
    t.date "start_date"
    t.boolean "task_notify", default: true
    t.integer "tasks_count", default: 0
    t.json "tokens"
    t.text "uid", default: "", null: false
    t.string "unlock_token"
    t.datetime "updated_at", precision: nil
    t.string "webauthn_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["organization_id"], name: "index_users_on_organization_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "version_associations", id: :serial, force: :cascade do |t|
    t.integer "foreign_key_id"
    t.string "foreign_key_name", null: false
    t.integer "version_id"
    t.index ["foreign_key_name", "foreign_key_id"], name: "index_version_associations_on_foreign_key"
    t.index ["version_id"], name: "index_version_associations_on_version_id"
  end

  create_table "versions", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.string "event", null: false
    t.integer "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.text "object_changes"
    t.integer "transaction_id"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
    t.index ["transaction_id"], name: "index_versions_on_transaction_id"
  end

  create_table "visit_clients", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "user_id"
    t.index ["user_id"], name: "index_visit_clients_on_user_id"
  end

  create_table "visits", id: :serial, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.integer "user_id"
    t.index ["user_id"], name: "index_visits_on_user_id"
  end

  create_table "webauthn_credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.datetime "last_used_at"
    t.string "nickname", null: false
    t.string "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["external_id"], name: "index_webauthn_credentials_on_external_id", unique: true
    t.index ["user_id", "nickname"], name: "index_webauthn_credentials_on_user_id_and_nickname", unique: true
    t.index ["user_id"], name: "index_webauthn_credentials_on_user_id"
  end

  add_foreign_key "able_screening_questions", "question_groups"
  add_foreign_key "able_screening_questions", "stages"
  add_foreign_key "agency_program_streams", "agencies", on_delete: :cascade
  add_foreign_key "agency_program_streams", "program_streams", on_delete: :cascade
  add_foreign_key "answers", "able_screening_questions"
  add_foreign_key "answers", "clients"
  add_foreign_key "assessment_domains_progress_notes", "assessment_domains"
  add_foreign_key "assessment_domains_progress_notes", "progress_notes"
  add_foreign_key "assessments", "clients"
  add_foreign_key "attachments", "able_screening_questions"
  add_foreign_key "attachments", "progress_notes"
  add_foreign_key "case_contracts", "cases"
  add_foreign_key "case_notes", "clients"
  add_foreign_key "case_worker_clients", "clients"
  add_foreign_key "case_worker_clients", "users"
  add_foreign_key "case_worker_tasks", "tasks"
  add_foreign_key "case_worker_tasks", "users"
  add_foreign_key "changelog_types", "changelogs"
  add_foreign_key "changelogs", "users"
  add_foreign_key "client_enrollment_search_entries", "client_enrollments", on_delete: :cascade
  add_foreign_key "client_enrollment_tracking_search_entries", "client_enrollment_trackings", on_delete: :cascade
  add_foreign_key "client_enrollment_trackings", "client_enrollments"
  add_foreign_key "client_enrollments", "clients"
  add_foreign_key "client_enrollments", "program_streams"
  add_foreign_key "client_quantitative_cases", "clients", on_delete: :cascade
  add_foreign_key "client_quantitative_cases", "quantitative_cases", on_delete: :cascade
  add_foreign_key "clients", "donors"
  add_foreign_key "custom_field_properties", "custom_fields"
  add_foreign_key "custom_field_property_search_entries", "custom_field_properties", on_delete: :cascade
  add_foreign_key "domains", "domain_groups"
  add_foreign_key "family_alerts", "families"
  add_foreign_key "family_alerts", "users", column: "created_by_id"
  add_foreign_key "family_alerts", "users", column: "resolved_by_id"
  add_foreign_key "family_notes", "families"
  add_foreign_key "family_notes", "users"
  add_foreign_key "google_task_events", "tasks", on_delete: :cascade
  add_foreign_key "google_task_events", "users", on_delete: :cascade
  add_foreign_key "interventions_progress_notes", "interventions"
  add_foreign_key "interventions_progress_notes", "progress_notes"
  add_foreign_key "leave_program_search_entries", "leave_programs", on_delete: :cascade
  add_foreign_key "leave_programs", "client_enrollments"
  add_foreign_key "progress_notes", "clients"
  add_foreign_key "progress_notes", "locations"
  add_foreign_key "progress_notes", "materials"
  add_foreign_key "progress_notes", "progress_note_types"
  add_foreign_key "progress_notes", "users"
  add_foreign_key "quantitative_cases", "quantitative_types", on_delete: :cascade
  add_foreign_key "quarterly_reports", "cases"
  add_foreign_key "surveys", "clients"
  add_foreign_key "tasks", "clients"
  add_foreign_key "thredded_messageboard_users", "thredded_messageboards"
  add_foreign_key "thredded_messageboard_users", "thredded_user_details"
  add_foreign_key "trackings", "program_streams"
  add_foreign_key "users", "organizations"
  add_foreign_key "visit_clients", "users"
  add_foreign_key "visits", "users"
  add_foreign_key "webauthn_credentials", "users"
end
