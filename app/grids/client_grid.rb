class ClientGrid
  extend ActionView::Helpers::TextHelper
  include Datagrid
  include ClientsHelper

  attr_accessor :current_user, :qType, :dynamic_columns, :visible_custom_field_ids
  # Phase 4 Tier 4 — clients.given_name/family_name/local_* are DETERMINISTICALLY encrypted. ORDER BY
  # clients.given_name would sort by opaque ciphertext, so the name term is dropped from the SQL ORDER
  # (clients.status, a plaintext enum, is kept). Alphabetical-by-name display ordering moves to Ruby in
  # `name_sorted_assets` below (mirrors the Tier 2 current_address + Tier 3 UserGrid name-order drops).
  scope do
    Client.includes({ cases: [:family, :partner] }, { client_enrollments: :program_stream }, :referral_source, :received_by, :followed_up_by, :province, :assessments, :birth_province).order('clients.status')
  end

  # UX round 3 (C2/R12) — the name sort options the UI offers. These are RUBY-side sorts (the
  # name columns are encrypted; SQL ORDER BY sorts ciphertext), so ClientGridOptions strips
  # them from what datagrid sees (unknown order => Datagrid::OrderUnsupported) and the
  # controller routes through name_sorted_assets + Kaminari.paginate_array instead.
  NAME_ORDERS = {
    'given_name'       => { by: :given_name,  descending: false },
    'given_name_desc'  => { by: :given_name,  descending: true  },
    'family_name'      => { by: :family_name, descending: false },
    'family_name_desc' => { by: :family_name, descending: true  }
  }.freeze

  # In-memory alphabetical-by-name ordering for the encrypted name columns: `assets` returns the
  # SQL-ordered relation (now status-only); decryption happens per-row in Ruby — acceptable for
  # the pilot's client volume (TODO: revisit around ~5k rows; would need a sortable digest column).
  # Zero-arg form keeps the legacy status-then-given-then-family contract (tier4 spec pins it);
  # by:/descending: back the C2 explicit first/last-name sorts.
  def name_sorted_assets(by: nil, descending: false)
    rows = assets.to_a
    sorted =
      if by.nil?
        rows.sort_by { |c| [c.status.to_s, c.given_name.to_s.downcase, c.family_name.to_s.downcase] }
      else
        secondary = by == :given_name ? :family_name : :given_name
        rows.sort_by { |c| [c.public_send(by).to_s.downcase, c.public_send(secondary).to_s.downcase] }
      end
    descending ? sorted.reverse : sorted
  end

  # UX round 3 (C1/R13) — the header quick search: first OR last name, case-insensitive,
  # whole-token equality (see Client.quick_name_search). Subquery on purpose: this grid's scope
  # carries heavy includes and Relation#or raises on structurally different relations.
  filter(:quick_search, :string, header: -> { I18n.t('datagrid.columns.clients.quick_search', default: 'Name (first or last)') }) do |value, scope|
    scope.where(id: Client.quick_name_search(value).select(:id))
  end

  filter(:given_name, :string, header: -> { I18n.t('datagrid.columns.clients.given_name') }) { |value, scope| scope.given_name_like(value) }

  filter(:family_name, :string, header: -> { I18n.t('datagrid.columns.clients.family_name') }) { |value, scope| scope.family_name_like(value) }



  # D4: full SOGI list, one source (Client::GENDER_OPTIONS). Straight where() — the old
  # block bucketed every non-'Male' value (including the capitalized default) as female.
  filter(:gender, :enum,
         select: -> { Client::GENDER_OPTIONS.map { |g| [I18n.t("clients.gender_options.#{g}", default: g.titleize), g] } },
         header: -> { I18n.t('datagrid.columns.clients.gender') }) do |value, scope|
    scope.where(gender: value)
  end

  filter(:slug, :string, header: -> { I18n.t('datagrid.columns.clients.id')})  { |value, scope| scope.slug_like(value) }

  filter(:code, :integer, header: -> { I18n.t('datagrid.columns.clients.code') }) { |value, scope| scope.start_with_code(value) }


  filter(:status, :enum, select: :status_options, header: -> { I18n.t('datagrid.columns.clients.status') })

  # filter(:house_number, :string)

  # Display-only US labels for the raw status enum. Filter VALUES stay the upstream strings
  # ('Active EC' etc.) so existing URLs (dashboard drill-downs, bookmarks) keep working; only
  # the dropdown labels change. XLS export still shows the raw status — accepted, ledgered.
  STATUS_LABELS = {
    'Active EC' => 'Active — Priority Intake',
    'Active FC' => 'Active — Sponsor Care',
    # Pre-production polish: KC is THE household case now (the single Add to Household
    # action) — its status is just "Active"; no care-placement vocabulary surfaces.
    'Active KC' => 'Active'
  }.freeze

  def status_options
    scope.status_like.map { |status| [STATUS_LABELS.fetch(status, status), status] }
  end


  # NOTE (deps datagrid 1.4.4 -> 2.0.9): a `range: true` filter block now receives a Range
  # (beginless/endless for one-sided input) where 1.4.4 handed a positional [from, to] Array.
  # `Range#second`/`Range#[]` do not exist and `Range#first` raises on a beginless range, so every
  # custom range block below reads bounds via `values.begin` / `values.end` instead.
  filter(:placement_date, :date, range: true, header: -> { I18n.t('datagrid.columns.clients.placement_start_date') }) do |values, scope|
    if values.begin.present? && values.end.present?
      ids = Client.joins(:cases).where(cases: { start_date: values }).pluck(:id).uniq
      scope.where(id: ids)
    elsif values.begin.present? && values.end.blank?
      ids = Client.joins(:cases).where('DATE(cases.start_date) >= ?', values.begin).pluck(:id).uniq
      scope.where(id: ids)
    elsif values.end.present? && values.begin.blank?
      ids = Client.joins(:cases).where('cases.start_date <= ?', values.end).pluck(:id).uniq
      scope.where(id: ids)
    end
  end

  # TODO: filter by placement date of both active and inactive cases
  # filter(:placement_case_type, :enum, select: %w(EC KC FC), header: -> { I18n.t('datagrid.columns.clients.placement_case_type') }) do |value, scope|
  #   ids = scope.joins(:cases).where(cases: { case_type: value }).pluck(:id).uniq
  #   scope.where(id: ids)
  # end

  filter(:date_of_birth, :date, range: true, header: -> { I18n.t('datagrid.columns.clients.date_of_birth') })

  filter(:age, :float, range: true, header: -> { I18n.t('datagrid.columns.clients.age') }) do |value, scope|
    scope.age_between(value.begin, value.end) if value.begin.present? && value.end.present?
  end

  filter(:has_date_of_birth, :enum, select: :has_or_has_no_dob, header: -> { I18n.t('datagrid.columns.clients.has_date_of_birth') }) do |value, scope|
    value == 'Yes' ? scope.where.not(date_of_birth: nil) : scope.where(date_of_birth: nil)
  end

  def has_or_has_no_dob
    [[I18n.t('datagrid.columns.clients.has_dob'), 'Yes'], [I18n.t('datagrid.columns.clients.no_dob'), 'No']]
  end

  # Country of Origin filter (pre-production polish): the one place the provinces list —
  # now the countries list — filters individuals. Only countries with at least one person.
  filter(:birth_province_id, :enum, select: :province_with_birth_place, header: -> { I18n.t('datagrid.columns.clients.birth_province', default: 'Country of Origin') })

  def province_with_birth_place
    Province.birth_places.map { |p| [p.name, p.id] }
  end

  # (Pre-production polish: the current-province/"State" filter+column left — provinces
  # hold Countries of Origin now; the birth-country shows on the individual's About grid.)

  filter(:initial_referral_date, :date, range: true, header: -> { I18n.t('datagrid.columns.clients.initial_referral_date') })

  filter(:referral_phone, :string, header: -> { I18n.t('datagrid.columns.clients.referral_phone') }) { |value, scope| scope.referral_phone_like(value) }

  filter(:received_by_id, :enum, select: :is_received_by_options, header: -> { I18n.t('datagrid.columns.clients.received_by') })

  def is_received_by_options
    current_user.present? ? Client.joins(:case_worker_clients).where(case_worker_clients: { user_id: current_user.id }).is_received_by : Client.is_received_by
  end
  # Client.joins(:case_worker_clients).where(case_worker_clients: { user_id: current_user.id })

  filter(:referral_source_id, :enum, select: :referral_source_options, header: -> { I18n.t('datagrid.columns.clients.referral_source') })

  def referral_source_options
    current_user.present? ? Client.joins(:case_worker_clients).where(case_worker_clients: { user_id: current_user.id }).referral_source_is : Client.referral_source_is
  end

  filter(:followed_up_by_id, :enum, select: :is_followed_up_by_options, header: -> { I18n.t('datagrid.columns.clients.follow_up_by') })

  def is_followed_up_by_options
    current_user.present? ? Client.joins(:case_worker_clients).where(case_worker_clients: { user_id: current_user.id }).is_followed_up_by : Client.is_followed_up_by
  end

  filter(:follow_up_date, :date, range: true, header: -> { I18n.t('datagrid.columns.clients.follow_up_date') })

  def agencies_options
    Agency.joins(:clients).pluck(:name).uniq
  end

  filter(:agencies_name, :enum, multiple: true, select: :agencies_options, header: -> { I18n.t('datagrid.columns.clients.agency_names') }) do |name, scope|
    if agencies ||= Agency.name_like(name)
      scope.joins(:agencies).where(agencies: { id: agencies.ids })
    else
      scope.joins(:agencies).where(agencies: { id: nil })
    end
  end

  filter(:grade, :integer, range: true, header: -> { I18n.t('datagrid.columns.clients.school_grade') })




  # filter(:user_id, :enum, select: :user_select_options, header: -> { I18n.t('datagrid.columns.clients.case_worker') })

  filter(:user_ids, :enum, multiple: true, select: :case_worker_options, header: -> { I18n.t('datagrid.columns.clients.case_worker') }) do |ids, scope|
    ids = ids.map{ |id| id.to_i }
    if user_ids ||= User.where(id: ids).ids
      client_ids = Client.joins(:users).where(users: { id: user_ids }).ids.uniq
      scope.where(id: client_ids)
    else
      scope.joins(:users).where(users: { id: nil })
    end
  end

  def case_worker_options
    User.has_clients.map { |user| ["#{user.first_name} #{user.last_name}", user.id] }
  end

  filter(:donor, :enum, select: :donor_select_options, header: -> { I18n.t('datagrid.columns.clients.donor') })

  def donor_select_options
    Donor.has_clients.map { |donor| [donor.name, donor.id] }
  end

  filter(:state, :enum, select: %w(Accepted Rejected), header: -> { I18n.t('datagrid.columns.clients.state') }) do |value, scope|
    value == 'Accepted' ? scope.accepted : scope.rejected
  end

  filter(:family_id, :integer, header: -> { I18n.t('datagrid.columns.families.code') }) do |value, object|
    # ids = []
    # Case.most_recents.joins(:client).group_by(&:client_id).each do |key, c|
    #   ids << c.first.id
    # end
    # # comment above, so user can search family_id of all family types they associate with
    object.joins(:cases).where("cases.family_id = ? ", value) if value.present?
  end

  def quantitative_type_options
    QuantitativeType.all.map{ |t| [t.name, t.id] }
  end

  filter(:quantitative_types, :enum, select: :quantitative_type_options, header: -> { I18n.t('datagrid.columns.clients.quantitative_types') }) do |value, scope|
    ids = Client.joins(:quantitative_cases).where(quantitative_cases: { quantitative_type_id: value.to_i }).pluck(:id).uniq
    scope.where(id: ids)
  end

  def quantitative_cases
    qType.present? ? QuantitativeType.find(qType.to_i).quantitative_cases.map{ |t| [t.value, t.id] } : QuantitativeCase.all.map{ |t| [t.value, t.id] }
  end

  filter(:quantitative_data, :enum, select: :quantitative_cases, header: -> { I18n.t('datagrid.columns.clients.quantitative_case_values') }) do |value, scope|
    ids = Client.joins(:quantitative_cases).where(quantitative_cases: { id: value.to_i }).pluck(:id).uniq
    scope.where(id: ids)
  end

  filter(:any_assessments, :enum, select: %w(Yes No), header: -> { I18n.t('datagrid.columns.clients.any_assessments') }) do |value, scope|
    if value == 'Yes'
      client_ids = Client.joins(:assessments).distinct.pluck(:id)
      scope.where(id: client_ids)
    else
      scope.without_assessments
    end
  end

  filter(:assessments_due_to, :enum, select: Assessment::DUE_STATES, header: -> { I18n.t('datagrid.columns.clients.assessments_due_to') }) do |value, scope|
    ids = []
    if value == Assessment::DUE_STATES[0]
      Client.all_active_types.each do |c|
        ids << c.id if c.next_assessment_date == Date.today
      end
    else
      Client.joins(:assessments).all_active_types.each do |c|
        ids << c.id if c.next_assessment_date < Date.today
      end
    end
    scope.where(id: ids)
  end

  # POAM-004 Unit 2: whitelisted numeric-comparison operators; no eval, no string interpolation.
  # `operation` is a user-selectable datagrid dynamic-filter operator -- an unknown/nil value fails closed.
  DOMAIN_SCORE_OPS = { '=' => :==, '==' => :==, '!=' => :!=, '>' => :>, '<' => :<, '>=' => :>=, '<=' => :<= }.freeze

  # datagrid 2.x passes the dynamic-filter block a Datagrid FilterValue (field/operation/value
  # accessors), not the 1.x [field, operation, value] array triple (deps program Phase 1d).
  # 2.x also introspects the selected field's column type at parse time (SELECT <field> FROM clients),
  # so the option VALUE must be a real column: keep the "All CSI" label but map it to :id (a valid
  # integer column). This block ignores the field entirely — it scores across every AssessmentDomain.
  filter(:all_domains, :dynamic, select: [['All CSI', 'id']], header: -> { I18n.t('datagrid.columns.clients.domains') }) do |filter, scope|
    operation = filter.operation
    value = filter.value.to_i
    assessment_id = []
    AssessmentDomain.all.group_by(&:assessment_id).each do |key, ad|
      arr = []
      a_id = []
      ad.each do |v|
        op = DOMAIN_SCORE_OPS[operation]
        arr.push(op ? v.score.to_i.public_send(op, value.to_i) : false)
        a_id.push v.assessment_id
      end
      if !arr.include?(false)
        assessment_id.push a_id[0]
      end
    end
    scope.joins(:assessments).where(assessments: { id: assessment_id })
  end

  # POAM-004 sibling: the 12 per-domain filters delegate here. `operation` is a user-selectable datagrid
  # dynamic-filter operator; interpolating it verbatim into the WHERE is the same SQLi/injection surface
  # all_domains was remediated for, and datagrid's `=~` DEFAULT_OPERATION reaches Postgres as `score=~ ?`
  # (PG::UndefinedFunction -> 500). Map the operator through a frozen whitelist to a SAFE SQL comparator
  # (parity with DOMAIN_SCORE_OPS); an unknown/injected/`=~` operator fails CLOSED (no rows, no execution).
  DOMAIN_SCORE_SQL_OPS = { '=' => '=', '==' => '=', '!=' => '!=', '>' => '>', '<' => '<', '>=' => '>=', '<=' => '<=' }.freeze

  def self.client_by_domain(operation, value, domain_id, scope)
    sql_op = DOMAIN_SCORE_SQL_OPS[operation]
    return scope.where(id: []) if sql_op.nil? # unknown/injected operator -> fail closed
    ids = Assessment.joins(:assessment_domains).where("score #{sql_op} ? AND domain_id = ?", value, domain_id).ids
    scope.joins(:assessments).where(assessments: { id: ids})
  end

  def self.get_domain(name)
    domain = Domain.find_by(name: name)
    domain.present?  ? Array.new([[domain.name, domain.id]]) : []
  end

  filter(:domain_1a, :dynamic, select: proc { get_domain('1A') }, header: -> { "#{ I18n.t('datagrid.columns.clients.domain')} 1A (Food Security)" }) do |filter, scope|
    client_by_domain(filter.operation, filter.value.to_i, filter.field, scope)
  end

  filter(:domain_1b, :dynamic, select: proc { get_domain('1B') }, header: -> { "#{ I18n.t('datagrid.columns.clients.domain')} 1B (Nutrition and Growth)" }) do |filter, scope|
    client_by_domain(filter.operation, filter.value.to_i, filter.field, scope)
  end

  filter(:domain_2a, :dynamic, select: proc { get_domain('2A') }, header: -> { "#{ I18n.t('datagrid.columns.clients.domain')} 2A (Shelter)" }) do |filter, scope|
    client_by_domain(filter.operation, filter.value.to_i, filter.field, scope)
  end

  filter(:domain_2b, :dynamic, select: proc { get_domain('2B') }, header: -> { "#{ I18n.t('datagrid.columns.clients.domain')} 2B (Care)" }) do |filter, scope|
    client_by_domain(filter.operation, filter.value.to_i, filter.field, scope)
  end

  filter(:domain_3a, :dynamic, select: proc { get_domain('3A') }, header: -> { "#{ I18n.t('datagrid.columns.clients.domain')} 3A (Protection from Abuse and Exploitation)" }) do |filter, scope|
    client_by_domain(filter.operation, filter.value.to_i, filter.field, scope)
  end

  filter(:domain_3b, :dynamic, select: proc { get_domain('3B') }, header: -> { "#{ I18n.t('datagrid.columns.clients.domain')} 3B (Legal Protection)" }) do |filter, scope|
    client_by_domain(filter.operation, filter.value.to_i, filter.field, scope)
  end

  filter(:domain_4a, :dynamic, select: proc { get_domain('4A') }, header: -> { "#{ I18n.t('datagrid.columns.clients.domain')} 4A (Wellness)" }) do |filter, scope|
    client_by_domain(filter.operation, filter.value.to_i, filter.field, scope)
  end

  filter(:domain_4b, :dynamic, select: proc { get_domain('4B') }, header: -> { "#{ I18n.t('datagrid.columns.clients.domain')} 4B (Health Care Services)" }) do |filter, scope|
    client_by_domain(filter.operation, filter.value.to_i, filter.field, scope)
  end

  filter(:domain_5a, :dynamic, select: proc { get_domain('5A') }, header: -> { "#{ I18n.t('datagrid.columns.clients.domain')} 5A (Emotional Health)" }) do |filter, scope|
    client_by_domain(filter.operation, filter.value.to_i, filter.field, scope)
  end

  filter(:domain_5b, :dynamic, select: proc { get_domain('5B') }, header: -> { "#{ I18n.t('datagrid.columns.clients.domain')} 5B (Social Behaviour)" }) do |filter, scope|
    client_by_domain(filter.operation, filter.value.to_i, filter.field, scope)
  end

  filter(:domain_6a, :dynamic, select: proc { get_domain('6A') }, header: -> { "#{ I18n.t('datagrid.columns.clients.domain')} 6A (Performance)" }) do |filter, scope|
    client_by_domain(filter.operation, filter.value.to_i, filter.field, scope)
  end

  filter(:domain_6b, :dynamic, select: proc { get_domain('6B') }, header: -> { "#{ I18n.t('datagrid.columns.clients.domain')} 6B (Work and Education)" }) do |filter, scope|
    client_by_domain(filter.operation, filter.value.to_i, filter.field, scope)
  end



  filter(:program_streams, :enum, multiple: true, select: :program_stream_options, header: -> { I18n.t('datagrid.columns.clients.program_streams') }) do |name, scope|
    program_stream_ids = ProgramStream.name_like(name).ids
    ids = Client.joins(:client_enrollments).where(client_enrollments: { program_stream_id: program_stream_ids } ).pluck(:id).uniq
    scope.where(id: ids)
  end

  def program_stream_options
    ProgramStream.joins(:client_enrollments).complete.ordered.pluck(:name).uniq
  end

  filter(:program_enrollment_date, :date, range: true, header: -> { I18n.t('datagrid.columns.clients.program_enrollment_date') }) do |values, scope|
    if values.begin.present? && values.end.present?
      ids = Client.joins(:client_enrollments).where(client_enrollments: { status: 'Active', enrollment_date: values} ).pluck(:id).uniq
      scope.where(id: ids)
    elsif values.begin.present? && values.end.blank?
      ids = Client.joins(:client_enrollments).where("DATE(client_enrollments.enrollment_date) >= ? AND client_enrollments.status = 'Active'", values.begin).pluck(:id).uniq
      scope.where(id: ids)
    elsif values.end.present? && values.begin.blank?
      ids = Client.joins(:client_enrollments).where("DATE(client_enrollments.enrollment_date) <= ? AND client_enrollments.status = 'Active'", values.end).pluck(:id).uniq
      scope.where(id: ids)
    end
  end

  filter(:program_exit_date, :date, range: true, header: -> { I18n.t('datagrid.columns.clients.program_exit_date') }) do |values, scope|
    if values.begin.present? && values.end.present?
      ids = ClientEnrollment.joins(:leave_program).where(leave_programs: {exit_date: values}).pluck(:client_id).uniq
      scope.where(id: ids)
    elsif values.begin.present? && values.end.blank?
      ids = ClientEnrollment.joins(:leave_program).where("DATE(leave_programs.exit_date) >= ?", values.begin).pluck(:client_id).uniq
      scope.where(id: ids)
    elsif values.end.present? && values.begin.blank?
      ids = ClientEnrollment.joins(:leave_program).where("DATE(leave_programs.exit_date) <= ?", values.end).pluck(:client_id).uniq
      scope.where(id: ids)
    end
  end

  filter(:accepted_date, :date, range: true, header: -> { I18n.t('datagrid.columns.clients.ngo_accepted_date') }) do |values, scope|
    if values.begin.present? && values.end.present?
      ids = Client.where(accepted_date: values).pluck(:id).uniq
      scope.where(id: ids)
    elsif values.begin.present? && values.end.blank?
      ids = Client.where('DATE(accepted_date) >= ?', values.begin).pluck(:id).uniq
      scope.where(id: ids)
    elsif values.end.present? && values.begin.blank?
      # was `=<` (not a PG operator) reading values.first (the blank lower bound) -> now `<=` on the upper bound.
      ids = Client.where('DATE(accepted_date) <= ?', values.end).pluck(:id).uniq
      scope.where(id: ids)
    end
  end

  filter(:exit_date, :date, range: true, header: -> { I18n.t('datagrid.columns.clients.ngo_exit_date') }) do |values, scope|
    if values.begin.present? && values.end.present?
      ids = Client.where(exit_date: values).pluck(:id).uniq
      scope.where(id: ids)
    elsif values.begin.present? && values.end.blank?
      ids = Client.where('DATE(exit_date) >= ?', values.begin).pluck(:id).uniq
      scope.where(id: ids)
    elsif values.end.present? && values.begin.blank?
      # was reading values.first (the blank lower bound) -> now the supplied upper bound.
      ids = Client.where('DATE(exit_date) <= ?', values.end).pluck(:id).uniq
      scope.where(id: ids)
    end
  end

  column(:slug, order:'clients.id', header: -> { I18n.t('datagrid.columns.clients.id') })

  column(:code, header: -> { I18n.t('datagrid.columns.clients.code') }) do |object|
    object.code ||= ''
  end


  # Tier 4: ORDER BY explicitly DISABLED on the encrypted name columns via `order: false`. Just removing
  # the `order:` option is NOT enough — Datagrid auto-derives orderability from the column name, so the
  # column would still emit ORDER BY clients.given_name (meaningless over ciphertext). Display is
  # unchanged — object.given_name/family_name decrypt transparently. Alphabetical-by-name ordering is
  # handled in Ruby via ClientGrid#name_sorted_assets.
  column(:given_name, order: false, header: -> { I18n.t('datagrid.columns.clients.given_name') }, html: true) do |object|
    link_to object.given_name, client_path(object)
  end

  column(:given_name, order: false, header: -> { I18n.t('datagrid.columns.clients.given_name') }, html: false)

  column(:family_name, order: false, header: -> { I18n.t('datagrid.columns.clients.family_name') })


  column(:gender, header: -> { I18n.t('datagrid.columns.clients.gender') }) do |object|
    object.gender_label
  end

  column(:status, header: -> { I18n.t('datagrid.columns.clients.status') }) do |object|
    format(object.status) do |value|
      status_style(value.to_s.sub(/\AActive .*/, "Active"))
    end
  end





  column(:program_streams, order: false, header: -> { I18n.t('datagrid.columns.clients.program_streams') }) do |object|
    object.client_enrollments.map{ |c| c.program_stream.name }.uniq.join(', ')
  end

  column(:program_enrollment_date, html: true, order: false, header: -> { I18n.t('datagrid.columns.clients.program_enrollment_date') }) do |object|
    render partial: 'clients/active_client_enrollments', locals: { active_client_enrollments: object.client_enrollments.active } if object.client_enrollments.active.any?
  end

  column(:program_enrollment_date, html: false, header: -> { I18n.t('datagrid.columns.clients.program_enrollment_date') }) do |object|
    object.client_enrollments.active.map{|a| a.enrollment_date }.join(' | ')
  end

  column(:program_exit_date, html: true, order: false, header: -> { I18n.t('datagrid.columns.clients.program_exit_date') }) do |object|
    # object.client_enrollments.inactive.joins(:leave_program).map{|ce| ce.leave_program.exit_date }
    render partial: 'clients/inactive_client_enrollments', locals: { inactive_client_enrollments: object.client_enrollments.inactive.joins(:leave_program) } if object.client_enrollments.inactive.joins(:leave_program).any?
  end

  column(:program_exit_date, html: false, header: -> { I18n.t('datagrid.columns.clients.program_exit_date') }) do |object|
    object.client_enrollments.inactive.joins(:leave_program).map{|a| a.leave_program.exit_date }.join(' | ')
  end



  column(:agency, order: false, header: -> { I18n.t('datagrid.columns.clients.agencies_involved') }) do |object|
    object.agencies.pluck(:name).join(', ')
  end

  column(:date_of_birth, header: -> { I18n.t('datagrid.columns.clients.date_of_birth') })

  column(:age, header: -> { I18n.t('datagrid.columns.clients.age') }, order: 'clients.date_of_birth desc') do |object|
    pluralize(object.age_as_years, 'year') + ' ' + pluralize(object.age_extra_months, 'month') if object.date_of_birth.present?
  end

  column(:current_address, order: false, header: -> { I18n.t('datagrid.columns.clients.current_address') })


  column(:school_name, header: -> { I18n.t('datagrid.columns.clients.school_name') })

  column(:grade, header: -> { I18n.t('datagrid.columns.clients.school_grade') })




  column(:state, header: -> { I18n.t('datagrid.columns.clients.state') }) do |object|
    object.state.titleize
  end

  column(:accepted_date, header: -> { I18n.t('datagrid.columns.clients.ngo_accepted_date') }) do |object|
    object.accepted_date
  end

  column(:exit_date, header: -> { I18n.t('datagrid.columns.clients.ngo_exit_date') }) do |object|
    object.exit_date
  end

  column(:rejected_note, header: -> { I18n.t('datagrid.columns.clients.rejected_note') })

  # column(:user, order: proc { |scope| scope.joins(:user).reorder('users.first_name') }, header: -> { I18n.t('datagrid.columns.clients.case_worker_or_staff') }) do |object|
  #   object.user.try(:name)
  # end

  column(:user, order: false, header: -> { I18n.t('datagrid.columns.clients.case_worker_or_staff') }) do |object|
    object.users.map{|u| u.name }.join(', ')
  end

  column(:donor, header: -> { I18n.t('datagrid.columns.clients.donor')}) do |object|
    object.donor_name
  end

  column(:case_start_date, order: false, header: -> { I18n.t('datagrid.columns.clients.placements.start_date') }) do |object|
    object.cases.current.try(:start_date)
  end






  column(:form_title, order: false, header: -> { I18n.t('datagrid.columns.clients.form_title') }, html: true) do |object|
    render partial: 'clients/client_custom_fields', locals: { object: object }
  end

  column(:form_title, header: -> { I18n.t('datagrid.columns.clients.form_title') }, html: false) do |object|
    object.custom_fields.pluck(:form_title).uniq.join(', ')
  end


  column(:family_id, order: false, header: -> { I18n.t('datagrid.columns.families.code') }) do |object|
    if object.cases.most_recents.first && object.cases.most_recents.first.family
      object.cases.most_recents.first.family.id
    end
  end

  column(:family, order: false, header: -> { I18n.t('datagrid.columns.clients.placements.family') }) do |object|
    if object.cases.most_recents.first && object.cases.most_recents.first.family
      object.cases.most_recents.first.family.name
    end
  end

  column(:partner, order: false, header: -> { I18n.t('datagrid.columns.partners.partner') }) do |object|
    if object.cases.current && object.cases.current.partner
      object.cases.current.partner.name
    end
  end

  column(:any_assessments, tag_options: { class: 'text-center' }, header: -> { I18n.t('datagrid.columns.clients.assessments') }, html: true) do |object|
    render partial: 'clients/assessments', locals: { object: object }
  end

  dynamic do
    next unless dynamic_columns.present?
    # Phase 5.3 (bypass A) — viewer's visible custom_field_id set, injected by the controller. nil FAILS
    # CLOSED to empty => formbuilder cells blank (over-mask, never a leak). Bulk/record-less => emergency_only never unlocked.
    vis_ids = visible_custom_field_ids || Set.new
    dynamic_columns.each do |column_builder|
      fields = column_builder[:id].split('_')
      cf_id  = column_builder[:custom_field_id]
      column(column_builder[:id].downcase.parameterize(separator: '_').to_sym, tag_options: { class: 'form-builder' }, header: -> { form_builder_format_header(fields) }, html: true) do |object|
        if fields.first == 'formbuilder'
          properties =
            if cf_id.present? && vis_ids.include?(cf_id)
              object.custom_field_properties.joins(:custom_field).where(custom_fields: { id: cf_id, entity_type: 'Client' }).properties_by(fields.last)
            else
              []
            end
        elsif fields.first == 'enrollment'
          properties = object.client_enrollments.joins(:program_stream).where(program_streams: { name: fields.second }).properties_by(fields.last)
        elsif fields.first == 'tracking'
          ids = object.client_enrollments.ids
          properties = ClientEnrollmentTracking.joins(:tracking).where(trackings: { name: fields.third }, client_enrollment_trackings: { client_enrollment_id: ids }).properties_by(fields.last)
        elsif fields.first == 'exitprogram'
          ids = object.client_enrollments.inactive.ids
          properties = LeaveProgram.joins(:program_stream).where(program_streams: { name: fields.second }, leave_programs: { client_enrollment_id: ids }).properties_by(fields.last)
        end
        render partial: 'clients/form_builder_dynamic/properties_value', locals: { properties:  properties }
      end
    end
  end

  dynamic do
    column(:changelog, html: true, tag_options: { class: 'text-center' }, header: -> { I18n.t('datagrid.columns.clients.changelogs') }) do |object|
      link_to t('datagrid.columns.clients.view'), client_version_path(object)
    end
  end
end
