class CustomFieldPropertiesController < AdminController
  load_and_authorize_resource

  include FormBuilderAttachments
  include SensitiveFields  # Phase 5.3

  before_action :find_entity, :find_custom_field
  before_action :enforce_sensitive_field_access, only: [:index]
  before_action :find_custom_field_property, only: [:edit, :update, :destroy]
  before_action :get_form_builder_attachments, only: [:edit, :update]

  def index
    visible = visible_custom_field_ids_for(@custom_formable)
    @custom_field_properties = @custom_formable.custom_field_properties
                                               .accessible_by(current_ability)
                                               .where(custom_field_id: visible.to_a)
                                               .by_custom_field(@custom_field)
                                               .most_recents
                                               .page(params[:page]).per(4)
  end

  def new
    @custom_field_property = @custom_formable.custom_field_properties.new(custom_field_id: @custom_field)
    @attachments = @custom_field_property.form_builder_attachments
    authorize! :new, @custom_field_property
  end

  def edit
    authorize! :edit, @custom_field_property
  end

  def create
    @custom_field_property = @custom_formable.custom_field_properties.new(custom_field_property_params)
    authorize! :create, @custom_field_property
    if @custom_field_property.save
      redirect_to polymorphic_path([@custom_formable, CustomFieldProperty], custom_field_id: @custom_field), notice: t('.successfully_created')
    else
      render :new
    end
  end

  def update
    authorize! :update, @custom_field_property
    if @custom_field_property.update(custom_field_property_params)
      add_more_attachments(@custom_field_property)
      redirect_to polymorphic_path([@custom_formable, CustomFieldProperty], custom_field_id: @custom_field), notice: t('.successfully_updated')
    else
      render :edit
    end
  end

  def destroy
    authorize! :destroy, @custom_field_property
    name = params[:file_name]
    index = params[:file_index].to_i
    if name.present? && index.present?
      delete_form_builder_attachment(@custom_field_property, name, index)
      redirect_to request.referer, notice: t('.delete_attachment_successfully')
    else
      @custom_field_property.destroy
      redirect_to polymorphic_path([@custom_formable, CustomFieldProperty], custom_field_id: @custom_field), notice: t('.successfully_deleted')
    end
  end

  private

  # Phase 5.3 — field-level guard: render the STATIC 403 (NOT raise CanCan::AccessDenied,
  # which redirects to root_url = 302). @custom_field is populated by find_custom_field (which 404s
  # an unknown form); load_and_authorize_resource enforces record :read first.
  def enforce_sensitive_field_access
    return if @custom_field.nil?
    return if visible_custom_field_ids_for(@custom_formable).include?(@custom_field.id)
    log_sensitive_field_denied(@custom_field)
    # Phase 5.4 — emergency_only + a break-glass-ELIGIBLE role (case worker / managers) with no
    # active grant: render the elevation PROMPT (reason -> POST /break_glass_grants) instead of a
    # dead end. restricted forms (role-based, no elevation path) and ineligible roles
    # (strategic_overviewer / nil — a grant would not widen their view) still get the static 403.
    # Either way the sensitive VALUES are never in the body.
    if @custom_field.sensitivity == SensitivityPolicy::EMERGENCY_ONLY && break_glass_eligible?
      @breakglass_custom_field = @custom_field
      @breakglass_formable     = @custom_formable
      return render template: 'break_glass_grants/prompt'
    end
    render plain: 'Not authorized', status: :forbidden, layout: false
  end

  def custom_field_property_params
    properties_params.values.map{ |v| v.delete('') if (v.is_a?Array) && v.size > 1 } if properties_params.present?

    default_params = params.require(:custom_field_property).permit({}).merge(custom_field_id: params[:custom_field_id])
    default_params = default_params.merge(properties: properties_params) if properties_params.present?
    default_params = default_params.merge(form_builder_attachments_attributes: attachment_params) if action_name == 'create' && attachment_params.present?
    default_params
  end

  def get_form_builder_attachments
    @attachments = @custom_field_property.form_builder_attachments
  end

  def find_custom_field_property
    @custom_field_property = @custom_formable.custom_field_properties.find(params[:id])
  end

  def find_custom_field
    @custom_field = CustomField.find_by(entity_type: @custom_formable.class.name, id: params[:custom_field_id])
    raise ActionController::RoutingError.new('Not Found') if @custom_field.nil?
  end

  def find_entity
    if params[:client_id].present?
      @custom_formable = Client.accessible_by(current_ability).friendly.find(params[:client_id])
    elsif params[:family_id].present?
      @custom_formable = Family.find(params[:family_id])
    elsif params[:partner_id].present?
      @custom_formable = Partner.find(params[:partner_id])
    elsif params[:user_id].present?
      @custom_formable = User.find(params[:user_id])
    end
  end

end
