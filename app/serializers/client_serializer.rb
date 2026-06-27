class ClientSerializer < ActiveModel::Serializer

  attributes  :id, :given_name, :family_name, :gender, :code, :status, :date_of_birth, :grade,
              :current_province, :local_given_name, :local_family_name, :kid_id, :donor,
              :current_address, :house_number, :street_number, :village, :commune, :district,
              :completed, :birth_province, :time_in_care, :initial_referral_date, :referral_source,
              :referral_phone, :live_with, :id_poor, :received_by,
              :followed_up_by, :follow_up_date, :school_name, :school_grade, :has_been_in_orphanage,
              :able_state, :has_been_in_government_care, :relevant_referral_information,
              :case_workers, :agencies, :state, :rejected_note, :emergency_care, :foster_care, :kinship_care,
              :organization, :additional_form, :tasks, :assessments, :case_notes, :quantitative_cases,
              :program_streams, :add_forms

  def case_workers
    object.users
  end

  def rejected_note
    object.rejected_note if object.status == "rejected"
  end

  def current_province
    object.province
  end

  def emergency_care
    # AMS 0.10 raises on Serializer.new(nil) (0.9 tolerated it); guard when there is no active case.
    client_case = object.cases.active.latest_emergency
    client_case ? CaseSerializer.new(client_case).serializable_hash : {}
  end

  def organization
    object.organization
  end

  def additional_form
    visible_ids = instance_options[:visible_custom_field_ids] || Set.new
    object.custom_fields.distinct.sort_by(&:form_title).select { |cf| visible_ids.include?(cf.id) }.map do |custom_field|
      custom_field.as_json.merge(custom_field_properties: custom_field.custom_field_properties.where(custom_formable_id: object.id, custom_field_id: visible_ids.to_a).as_json)
    end
  end

  def tasks
    overdue_tasks   = ActiveModelSerializers::SerializableResource.new(object.tasks.overdue_incomplete, each_serializer: TaskSerializer, adapter: :attributes).as_json
    today_tasks     = ActiveModelSerializers::SerializableResource.new(object.tasks.today_incomplete, each_serializer: TaskSerializer, adapter: :attributes).as_json
    upcoming_tasks  = ActiveModelSerializers::SerializableResource.new(object.tasks.incomplete.upcoming, each_serializer: TaskSerializer, adapter: :attributes).as_json
    { overdue: overdue_tasks, today: today_tasks, upcoming: upcoming_tasks }
  end

  def case_notes
    object.case_notes.most_recents
  end

  def foster_care
    client_case = object.cases.active.latest_foster
    client_case ? CaseSerializer.new(client_case).serializable_hash : {}
  end

  def kinship_care
    client_case = object.cases.active.latest_kinship
    client_case ? CaseSerializer.new(client_case).serializable_hash : {}
  end

  def assessments
    levels = visible_domain_levels_option
    object.assessments.map do |assessment|
      formatted_assessment_domain = assessment.assessment_domains_in_order.select { |ad| ad.domain && levels.include?(ad.domain.sensitivity) }.map do |ad|
        incomplete_tasks = object.tasks.by_domain_id(ad.domain_id).incomplete
        ad.as_json.merge(domain: ad.domain.as_json(only: [:name, :identity]), incomplete_tasks: incomplete_tasks.as_json(only: [:name, :id]))
      end
      assessment.as_json.merge(assessment_domain: formatted_assessment_domain)
    end
  end

  def case_notes
    levels = visible_domain_levels_option
    object.case_notes.most_recents.map do |case_note|
      formatted_case_note_domain_group = case_note.case_note_domain_groups.map do |cdg|
        next if cdg.domain_group.nil?
        domain_scores = cdg.domain_group.domains.map do |domain|
          next unless levels.include?(domain.sensitivity)
          ad = domain.assessment_domains.find_by(assessment_id: case_note.assessment_id)
          { domain_id: ad.domain_id, score: ad.score } if ad.present?
        end.compact
        cdg.as_json.merge(domain_group_identities: cdg.domain_group.domain_identities, domain_scores: domain_scores, completed_tasks: cdg.completed_tasks)
      end
      case_note.as_json.merge(case_note_domain_group: formatted_case_note_domain_group)
    end
  end

  def quantitative_cases
    object.quantitative_cases.group_by(&:quantitative_type).map do |qtypes|
      qtype = qtypes.first.name
      qcases = qtypes.last.map{ |qcase| qcase.value }
      { quantitative_type: qtype, client_quantitative_cases: qcases }
    end
  end

  def program_streams
    object.program_streams.map do |program_stream|
      formatted_enrollments = program_stream.client_enrollments.map do |enrollment|
        trackings = enrollment.client_enrollment_trackings
        leave_program = enrollment.leave_program
        enrollment.as_json.merge( trackings: trackings, leave_program: leave_program )
      end
      domains = program_stream.domains.map(&:identity)
      program_stream.as_json(only: [:id, :name, :description, :quantity]).merge(domain: domains, enrollments: formatted_enrollments)
    end
  end

  def add_forms
    visible_ids = instance_options[:visible_custom_field_ids] || Set.new
    custom_field_ids = object.custom_field_properties.pluck(:custom_field_id)
    CustomField.client_forms.not_used_forms(custom_field_ids).order_by_form_title.where(id: visible_ids.to_a)
  end

  private

  # Phase 5.3 — viewer's permitted Domain levels (instance option from api/clients#compare). Defaults
  # standard-only so a render that omits the option fails closed rather than leaking restricted scores.
  def visible_domain_levels_option
    Array(instance_options[:visible_domain_levels].presence || [SensitivityPolicy::STANDARD])
  end

end
