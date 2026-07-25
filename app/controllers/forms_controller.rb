# UX round 3 (A1) — the merged Forms partition page: every filled custom form for a record,
# Programs-page style (filled table + available-to-add table), replacing the Overview Forms
# card. Per-form dated ENTRIES stay on custom_field_properties#index (the "trackings" view).
# Polymorphic like CustomFieldPropertiesController: clients now, families when their hub lands.
class FormsController < AdminController
  include SensitiveFields # Phase 5.3/5.4 — visible form set + break-glass candidates

  before_action :find_entity

  def index
    # AdminController has no check_authorization; authorize the record read explicitly so the
    # page behaves identically under the Phase-5.6 enforcement flags.
    authorize! :read, @custom_formable
    filled_ids = @custom_formable.custom_field_properties.pluck(:custom_field_id)
    visible    = visible_custom_field_ids_for(@custom_formable) # record-aware (break-glass folds in)
    @grouped_forms = @custom_formable.custom_field_properties
                                     .includes(:custom_field)
                                     .where(custom_field_id: visible.to_a)
                                     .group_by(&:custom_field_id)
                                     .sort_by { |_, props| props.first.custom_field.form_title.to_s }
                                     .to_h
    @available_forms  = CustomField.public_send(form_scope)
                                   .not_used_forms(filled_ids)
                                   .where(id: visible.to_a)
                                   .order_by_form_title
    # Phase 5.4 — emergency_only forms (with data) the viewer could break-glass into; rendered
    # as locked rows with the per-form elevation modal (moved here from the Overview card).
    @breakglass_forms = breakglass_form_candidates(@custom_formable)
  end

  private

  def find_entity
    if params[:client_id].present?
      @custom_formable = Client.accessible_by(current_ability).friendly.find(params[:client_id])
    elsif params[:family_id].present?
      @custom_formable = Family.find(params[:family_id])
    else
      raise ActionController::RoutingError, 'Not Found'
    end
  end

  def form_scope
    @custom_formable.is_a?(Family) ? :family_forms : :client_forms
  end
end
