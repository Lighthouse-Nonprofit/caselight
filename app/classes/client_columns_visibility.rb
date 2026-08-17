class ClientColumnsVisibility
  def initialize(grid, params)
    @grid   = grid
    @params = params
  end

  def columns_collection
    {
      program_streams_: :program_streams,
      program_enrollment_date_: :program_enrollment_date,
      program_exit_date_: :program_exit_date,
      given_name_: :given_name,
      family_name_: :family_name,
      gender_: :gender,
      date_of_birth_: :date_of_birth,
      status_: :status,
      agencies_name_: :agency,
      current_address_: :current_address,
      school_name_: :school_name,
      grade_: :grade,
      user_ids_: :user,
      state_: :state,
      accepted_date_: :accepted_date,
      exit_date_: :exit_date,
      rejected_note_: :rejected_note,
      case_start_date_: :case_start_date,
      form_title_: :form_title,
      family_: :family,
      partner_: :partner,
      code_: :code,
      age_: :age,
      slug_: :slug,
      family_id_: :family_id,
      any_assessments_: :any_assessments,
      changelog_: :changelog
    }
  end

  def visible_columns
    @grid.column_names = []
    static_keys = columns_collection.keys
    add_custom_builder_columns.each do |key, value|
      next unless @params[key]
      # Guard stale bookmarked params: a STATIC column the grid no longer defines (e.g. the
      # province/State column removed 2026-07-31) makes Datagrid raise on render — a blank 500.
      # Dynamic form-builder columns are instance-added, so only static keys get the class check.
      next if static_keys.include?(key) && @grid.class.column_by_name(value).nil?
      @grid.column_names << value
    end
  end

  def add_custom_builder_columns
    columns = columns_collection
    if @params[:column_form_builder].present?
      @params[:column_form_builder].each do |column|
        field   = column['id'].downcase.parameterize(separator: '_')
        columns = columns.merge!("#{field}_": field.to_sym)
      end
    end
    columns
  end
end
