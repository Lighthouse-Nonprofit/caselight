class DataTrackersController < AdminController
  load_and_authorize_resource
  include SensitiveFields  # Phase 5.3 — supplies current_user; masking via SensitiveVersionScope

  before_action :find_form_type, :find_item_type

  def index
    page     = params[:per_page] || 20
    per_page = page.to_i

    if @item_type.present?
      if @form_type.present?
        relation = filter_custom_field_versions
      else
        relation = PaperTrail::Version.where(item_type: params[:item_type])
      end
    else
      relation = PaperTrail::Version.where.not(item_type: exclude_item_type)
    end
    relation = relation.order(created_at: :desc)
    # Phase 5.3 — for the CustomFieldProperty version surface, drop versions this viewer may not see.
    # Re-scope to an AR relation by surviving ids so the view's @versions.decorate + Kaminari work
    # (filter_versions returns an Array; we must NOT hand a PaginatableArray to .decorate). break_glass:[]
    # (bulk audit, emergency never unlocked). Other item_types paginate unchanged.
    if @item_type == 'CustomFieldProperty'
      kept_ids  = SensitiveVersionScope.visible_version_ids(relation, user: current_user, break_glass: [])
      @versions = PaperTrail::Version.where(id: kept_ids).order(created_at: :desc).page(params[:page]).per(per_page)
    else
      @versions = relation.page(params[:page]).per(per_page)
    end
  end

  private

  def exclude_item_type
    %w(AssessmentDomain CaseNoteDomainGroup CaseNote AgencyClient ClientQuantitativeCase ClientCustomField FamilyCustomField PartnerCustomField UserCustomField)
  end

  def find_form_type
    @form_type = params[:formable_type]
  end

  def find_item_type
    @item_type = params[:item_type]
  end

  def filter_custom_field_versions
    PaperTrail::Version
      .where(item_type: @item_type)
      .where("object ILIKE '%custom_formable_type: #{@form_type}%' OR object_changes ILIKE '%custom_formable_type:\n- \n- #{@form_type}%'")
  end

end
