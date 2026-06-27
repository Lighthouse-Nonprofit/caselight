class FamiliesController < AdminController
  include SensitiveFields  # Phase 5.3
  load_and_authorize_resource

  before_action :find_association, except: [:index, :destroy, :version]
  before_action :find_family, only: [:show, :edit, :update, :destroy]

  def index
    @family_grid = FamilyGrid.new(params[:family_grid])
    respond_to do |f|
      f.html do
        @results = @family_grid.assets.size
        @family_grid.scope { |scope| scope.page(params[:page]).per(20) }
      end
      f.xls do
        send_data @family_grid.to_xls, filename: "family_report-#{Time.now}.xls"
      end
    end
  end

  def new
    @family = Family.new
  end

  def create
    @family = Family.new(family_params)
    if @family.save
      redirect_to @family, notice: t('.successfully_created')
    else
      render :new
    end
  end

  def show
    custom_field_ids            = @family.custom_field_properties.pluck(:custom_field_id)
    visible = visible_custom_field_ids_for(@family)
    @group_family_custom_fields = @family.custom_field_properties
                                         .where(custom_field_id: visible.to_a)
                                         .group_by(&:custom_field_id)
    @free_family_forms          = CustomField.family_forms
                                             .not_used_forms(custom_field_ids)
                                             .where(id: visible.to_a)
                                             .order_by_form_title
    @client_grid = ClientGrid.new(params.fetch(:client_grid, {}).merge!(family_id: @family.id))
    # Phase 5.3 — bulk grid gets the RECORD-LESS set (emergency never unlocked). Guard with respond_to?
    # so this is order-independent of the client_grid.rb attr_accessor edit.
    @client_grid.visible_custom_field_ids = visible_custom_field_ids if @client_grid.respond_to?(:visible_custom_field_ids=)
    @results = @client_grid.assets.distinct.size
    @client_grid.scope { |scope| scope.page(params[:page]).per(5).distinct }
  end

  def edit
  end

  def update
    if client_associations.any? && @family.is_case?
      redirect_to request.referrer, alert: t('.not_allowed_to_detach_clients')
    else
      if @family.update(family_params)
        redirect_to @family, notice: t('.successfully_updated')
      else
        render :edit
      end
    end
  end

  def destroy
    if @family.cases_count.zero?
      @family.destroy
      redirect_to families_url, notice: t('.successfully_deleted')
    else
      redirect_to families_url, alert: t('.alert')
    end
  end

  def version
    page      = params[:per_page] || 20
    @family   = Family.find(params[:family_id])
    relation  = @family.versions.reorder(created_at: :desc)
    kept_ids  = SensitiveVersionScope.visible_version_ids(relation, user: current_user, break_glass: [])
    @versions = relation.where(id: kept_ids).reorder(created_at: :desc).page(params[:page]).per(page.to_i)
  end

  private

  def family_params

    params.require(:family).permit(
                            :name, :code, :case_history, :caregiver_information,
                            :significant_family_member_count, :household_income,
                            :dependable_income, :female_children_count,
                            :male_children_count, :female_adult_count,
                            :male_adult_count, :family_type, :contract_date,
                            :address, :province_id,
                            custom_field_ids: [],
                            client_ids: []
                            )
  end

  def find_association
    # Phase 4 Tier 4: clients.given_name/family_name are DETERMINISTICALLY encrypted; ORDER BY them sorts
    # by ciphertext. Drop the SQL order and sort alphabetically in Ruby on the decrypted names (the
    # association list is small). .distinct runs on the relation BEFORE materializing to an array.
    @clients  = Client.accessible_by(current_ability).joins('LEFT OUTER JOIN cases ON cases.client_id = clients.id').where('cases.family_id = ? OR (clients.status = ? AND clients.state = ?)', @family.id, 'Referred', 'accepted').distinct.to_a.sort_by { |c| [c.given_name.to_s.downcase, c.family_name.to_s.downcase] }
    @province = Province.order(:name)
  end

  def find_family
    @family = Family.find(params[:id])
  end

  def client_associations
    @family.client_ids.uniq - params[:family][:client_ids].map{|a| a.to_i }
  end
end
