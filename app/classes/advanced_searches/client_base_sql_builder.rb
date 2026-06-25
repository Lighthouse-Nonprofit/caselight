module AdvancedSearches
  class ClientBaseSqlBuilder
    ASSOCIATION_FIELDS = ['user_id', 'case_type', 'agency_name', 'form_title', 'placement_date', 'family', 'age', 'family_id', 'referred_to_ec', 'referred_to_fc', 'referred_to_kc', 'exit_ec_date', 'exit_fc_date', 'exit_kc_date', 'program_stream']
    BLANK_FIELDS = ['date_of_birth', 'initial_referral_date', 'follow_up_date', 'has_been_in_orphanage', 'has_been_in_government_care', 'grade', 'province_id', 'referral_source_id', 'birth_province_id', 'received_by_id', 'followed_up_by_id', 'donor_id', 'id_poor', 'exit_date', 'accepted_date']

    # Phase 4 Tier 4: DETERMINISTICALLY-encrypted client name columns. base_sql cannot query these with
    # raw `clients.<col> = ?` (the column holds a ciphertext envelope, not the plaintext). They are
    # resolved via the model's deterministic-equality *_like scopes to a list of ids and emitted as
    # `clients.id IN (?)`. Only equal/not_equal/is_empty/is_not_empty arrive (FilterTypes.text_equal_options).
    NAME_ENCRYPTED_FIELDS = ['given_name', 'family_name', 'local_given_name', 'local_family_name'].freeze

    def initialize(clients, rules)
      @clients     = clients
      @values      = []
      @sql_string  = []
      @condition    = rules['condition']
      @basic_rules  = rules['rules'] || []

      @columns_visibility = []
    end

    def generate
      @basic_rules.each do |rule|
        field    = rule['field']
        operator = rule['operator']
        value    = rule['value']
        form_builder = field != nil ? field.split('_') : []
        if ASSOCIATION_FIELDS.include?(field)
          association_filter = AdvancedSearches::ClientAssociationFilter.new(@clients, field, operator, value).get_sql
          @sql_string << association_filter[:id]
          @values     << association_filter[:values]

        elsif form_builder.first == 'formbuilder'
          custom_form = CustomField.find_by(form_title: form_builder.second)
          custom_field = AdvancedSearches::ClientCustomFormSqlBuilder.new(custom_form, rule).get_sql
          @sql_string << custom_field[:id]
          @values << custom_field[:values]

        elsif form_builder.first == 'enrollment'
          program_stream = ProgramStream.find_by(name: form_builder.second)
          enrollment_fields = AdvancedSearches::EnrollmentSqlBuilder.new(program_stream.id, rule).get_sql
          @sql_string << enrollment_fields[:id]
          @values << enrollment_fields[:values]

        elsif form_builder.first == 'enrollmentdate'
          program_stream = ProgramStream.find_by(name: form_builder.second)
          enrollment_date = AdvancedSearches::EnrollmentDateSqlBuilder.new(program_stream.id, rule).get_sql
          @sql_string << enrollment_date[:id]
          @values << enrollment_date[:values]

        elsif form_builder.first == 'tracking'
          tracking = Tracking.joins(:program_stream).where(program_streams: {name: form_builder.second}, trackings: {name: form_builder.third}).last
          tracking_fields = AdvancedSearches::TrackingSqlBuilder.new(tracking.id, rule).get_sql
          @sql_string << tracking_fields[:id]
          @values << tracking_fields[:values]

        elsif form_builder.first == 'exitprogram'
          program_stream = ProgramStream.find_by(name: form_builder.second)
          exit_program_fields = AdvancedSearches::ExitProgramSqlBuilder.new(program_stream.id, rule).get_sql
          @sql_string << exit_program_fields[:id]
          @values << exit_program_fields[:values]

        elsif form_builder.first == 'programexitdate'
          program_stream = ProgramStream.find_by(name: form_builder.second)
          exit_date = AdvancedSearches::ProgramExitDateSqlBuilder.new(program_stream.id, rule).get_sql
          @sql_string << exit_date[:id]
          @values << exit_date[:values]

        elsif form_builder.first == 'quantitative'
          quantitative_filter = AdvancedSearches::QuantitativeCaseSqlBuilder.new(@clients, rule).get_sql
          @sql_string << quantitative_filter[:id]
          @values << quantitative_filter[:values]

        elsif NAME_ENCRYPTED_FIELDS.include?(field)
          name_filter = name_encrypted_sql(field, operator, value)
          @sql_string << name_filter[:id]
          @values     << name_filter[:values]

        elsif field != nil
          value = field == 'grade' ? validate_integer(value) : value
          base_sql(field, operator, value)

        else
          nested_query =  AdvancedSearches::ClientBaseSqlBuilder.new(@clients, rule).generate
          @sql_string << nested_query[:sql_string]
          nested_query[:values].select{ |v| @values << v }
        end
      end

      @sql_string = @sql_string.join(" #{@condition} ")
      @sql_string = "(#{@sql_string})" if @sql_string.present?
      { sql_string: @sql_string, values: @values }
    end

    private

    # Phase 4 Tier 4: resolve an equality/inequality predicate on a DETERMINISTICALLY-encrypted name
    # column to a `clients.id IN (?)` clause via the model's *_like scope (rewritten to deterministic
    # equality `where(col: value)`). Substring operators are not offered for these fields
    # (FilterTypes.text_equal_options), so only equal / not_equal / is_empty / is_not_empty arrive.
    # is_empty / is_not_empty test the DECRYPTED value in Ruby (a ciphertext column cannot be NULL/''-
    # tested in SQL); acceptable for the small pilot client volume. The returned `values` is the id
    # ARRAY — generate appends it as ONE element of @values against the single `IN (?)` placeholder; the
    # consumer (ClientAdvancedSearch#filter) binds each @values element once and Rails expands the array.
    def name_encrypted_sql(field, operator, value)
      scope = "#{field}_like".to_sym
      ids =
        case operator
        when 'equal'
          @clients.public_send(scope, value).ids
        when 'not_equal'
          @clients.where.not(id: @clients.public_send(scope, value).ids).ids
        when 'is_empty'
          @clients.reject { |c| c.public_send(field).present? }.map(&:id)
        when 'is_not_empty'
          @clients.select { |c| c.public_send(field).present? }.map(&:id)
        else
          []
        end
      { id: 'clients.id IN (?)', values: ids }
    end

    def base_sql(field, operator, value)
      case operator
      when 'equal'
        @sql_string << "clients.#{field} = ?"
        @values << value

      when 'not_equal'
        @sql_string << "clients.#{field} != ?"
        @values << value

      when 'less'
        @sql_string << "clients.#{field} < ?"
        @values << value

      when 'less_or_equal'
        @sql_string << "clients.#{field} <= ?"
        @values << value

      when 'greater'
        @sql_string << "clients.#{field} > ?"
        @values << value

      when 'greater_or_equal'
        @sql_string << "clients.#{field} >= ?"
        @values << value

      when 'contains'
        @sql_string << "clients.#{field} ILIKE ?"
        @values << "%#{value}%"

      when 'not_contains'
        @sql_string << "clients.#{field} NOT ILIKE ?"
        @values << "%#{value}%"

      when 'is_empty'
        if BLANK_FIELDS.include? field
          @sql_string << "clients.#{field} IS NULL"
        else
          @sql_string << "(clients.#{field} IS NULL OR clients.#{field} = '')"
        end

      when 'is_not_empty'
        if BLANK_FIELDS.include? field
          @sql_string << "clients.#{field} IS NOT NULL"
        else
          @sql_string << "(clients.#{field} IS NOT NULL AND clients.#{field} != '')"
        end

      when 'between'
        @sql_string << "clients.#{field} BETWEEN ? AND ?"
        @values << value.first
        @values << value.last
      end
    end

    def validate_integer(values)
      if values.is_a?(Array)
        first_value = values.first.to_i > 1000000 ? "1000000" : values.first
        last_value  = values.last.to_i > 1000000 ? "1000000" : values.last
        [first_value, last_value]
      else
        values.to_i > 1000000 ? "1000000" : values
      end
    end
  end
end
