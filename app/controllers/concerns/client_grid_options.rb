module ClientGridOptions
  extend ActiveSupport::Concern
  include ClientsHelper
  included { include SensitiveFields }   # Phase 5.3 — record-less visible_custom_field_ids + visible_domain_levels

  def choose_grid
    if current_user.admin? || current_user.strategic_overviewer?
      admin_client_grid
    elsif current_user.case_worker? || current_user.any_manager?
      non_admin_client_grid
    end
  end

  # UX round 3 (C2/R12): the name sorts are Ruby-side (encrypted columns). Strip a NAME_ORDERS
  # order from what ClientGrid.new sees — datagrid raises Datagrid::OrderUnsupported on orders
  # that aren't SQL-orderable columns — and stash it for the controller, which routes through
  # name_sorted_assets + Kaminari.paginate_array. Raw params stay intact for the view (the
  # select's selected option + the sort form's hidden-field replay). XLS exports come through
  # here too, so a name order never reaches the export path (stays status-ordered).
  def client_grid_params
    grid_params = params.fetch(:client_grid, {})
    order = grid_params[:order].to_s
    return grid_params unless ClientGrid::NAME_ORDERS.key?(order)
    @name_sort = ClientGrid::NAME_ORDERS[order]
    grid_params.except(:order, :descending)
  end

  def columns_visibility
    @client_columns ||= ClientColumnsVisibility.new(@client_grid, params.merge(column_form_builder: column_form_builder))
    @client_columns.visible_columns
  end

  def domain_score_report
    return unless params['type'] == 'basic_info'
    levels = visible_domain_levels   # Phase 5.3 — per-viewer; admin/restricted-roles keep their scores, NOT forced standard-only
    @client_grid.column(:assessments, header: t('.assessments')) do |client|
      client.assessments.map { |a| a.basic_info(levels) }.join("\x0D\x0A")
    end
    @client_grid.column_names << :assessments if @client_grid.column_names.any?
  end

  def form_builder_report
    vis_ids = visible_custom_field_ids   # Phase 5.3 — record-less bulk set; emergency never unlocked here
    column_form_builder.each do |field|
      fields = field[:id].split('_')
      cf_id  = field[:custom_field_id]
      @client_grid.column(field[:id].downcase.parameterize(separator: '_').to_sym, header: form_builder_format_header(fields)) do |client|
        if fields.first == 'formbuilder'
          if cf_id.present? && vis_ids.include?(cf_id)
            client.custom_field_properties.joins(:custom_field).where(custom_fields: { id: cf_id, entity_type: 'Client' }).properties_by(fields.last).map { |p| format_properties_value(p) }.join("\n")
          else
            ''
          end
        elsif fields.first == 'enrollment'
          client.client_enrollments.joins(:program_stream).where(program_streams: { name: fields.second }).properties_by(fields.last).map { |p| format_properties_value(p) }.join("\n")
        elsif fields.first == 'tracking'
          ids = client.client_enrollments.ids
          ClientEnrollmentTracking.joins(:tracking).where(trackings: { name: fields.third }, client_enrollment_trackings: { client_enrollment_id: ids }).properties_by(fields.last).map { |p| format_properties_value(p) }.join("\n")
        elsif fields.first == 'exitprogram'
          ids = client.client_enrollments.inactive.ids
          LeaveProgram.joins(:program_stream).where(program_streams: { name: fields.second }, leave_programs: { client_enrollment_id: ids }).properties_by(fields.last).map { |p| format_properties_value(p) }.join("\n")
        end
      end
    end
  end

  def admin_client_grid
    # Phase 5.3 — inject the record-less visible custom_field_id set AT CONSTRUCTION. datagrid 2.0
    # evaluates the `dynamic do` formbuilder-masking block during ClientGrid.new, and the cells render
    # in the view context, so the gate must close over the set captured at build time — assigning it
    # after `.new` (the old order) left the gate an empty Set and OVER-masked every viewer.
    vis_ids = visible_custom_field_ids
    if params[:client_grid] && params[:client_grid][:quantitative_types]
      quantitative_types = params[:client_grid][:quantitative_types]
      @client_grid = ClientGrid.new(client_grid_params.merge!(qType: quantitative_types, dynamic_columns: column_form_builder, visible_custom_field_ids: vis_ids))
    else
      @client_grid = ClientGrid.new(client_grid_params.merge!(dynamic_columns: column_form_builder, visible_custom_field_ids: vis_ids))
    end
    @client_grid
  end

  def non_admin_client_grid
    # Phase 5.3 — inject the visible custom_field_id set AT CONSTRUCTION (see admin_client_grid).
    vis_ids = visible_custom_field_ids
    if params[:client_grid] && params[:client_grid][:quantitative_types]
      quantitative_types = params[:client_grid][:quantitative_types]
      @client_grid = ClientGrid.new(client_grid_params.merge!(current_user: current_user, qType: quantitative_types, dynamic_columns: column_form_builder, visible_custom_field_ids: vis_ids))
    else
      @client_grid = ClientGrid.new(client_grid_params.merge!(current_user: current_user, dynamic_columns: column_form_builder, visible_custom_field_ids: vis_ids))
    end
    @client_grid
  end

  def column_form_builder
    if @custom_form_fields.present? || @program_stream_fields.present?
      @custom_form_fields + @program_stream_fields
    else
      []
    end
  end

  def form_builder_params
    params[:form_builder].present? ? nil : column_form_builder
  end
end
