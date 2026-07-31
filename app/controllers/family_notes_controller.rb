# UX round 3 (B2) — household-level notes (the family hub's Notes tab). CaseNotesController-lite:
# no assessment/domain machinery, just dated narrative CRUD. Reads are audited (AU-2/AU-12 —
# family notes are narrative PII like case notes).
class FamilyNotesController < AdminController
  include AccessAudit
  include SensitiveFields # the family header's Forms chip reads visible_custom_field_ids_for

  prepend_before_action :set_family
  load_and_authorize_resource through: :family

  def index
    @family_notes = @family_notes.most_recents.page(params[:page]).per(10)
  end

  def new
    @family_note.meeting_date ||= Time.zone.today
  end

  def create
    @family_note.user = current_user
    if @family_note.save
      redirect_to family_family_notes_path(@family), notice: t('.successfully_created')
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @family_note.update(family_note_params)
      redirect_to family_family_notes_path(@family), notice: t('.successfully_updated')
    else
      render :edit
    end
  end

  def destroy
    @family_note.destroy
    redirect_to family_family_notes_path(@family), notice: t('.successfully_deleted')
  end

  private

  def set_family
    @family = Family.accessible_by(current_ability).find(params[:family_id])
  end

  def family_note_params
    params.require(:family_note).permit(:meeting_date, :attendee, :note)
  end
end
