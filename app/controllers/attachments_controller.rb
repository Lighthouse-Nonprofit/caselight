class AttachmentsController < AdminController
  # Phase 5.6 (AC-3): this was a genuine DEFAULT-OPEN hole (zero authorization). #index returned attachment
  # records for ANY progress_note_id; #delete DESTROYED attachments by id -- both with no CanCan check.
  # Resolved with a REAL authorize! (NOT skip_authorization_check), GATED behind enforce_authorization? so
  # the flag-OFF behavior is byte-identical to today (SHADOW-FIRST: while OFF these surface as
  # authorization_shadow rows, not denials). Under enforcement, read-only roles are correctly denied while
  # the progress-note/case-note editors (who hold :read AND :destroy Attachment) keep working.
  def index
    authorize! :read, Attachment if enforce_authorization?
    @attachments = Attachment.where(progress_note_id: params[:progress_note_id])
    render json: @attachments, status: 200
  end

  def delete
    authorize! :destroy, Attachment if enforce_authorization?
    if params[:attachments]
      attachments = params[:attachments]
      Attachment.destroy(attachments)
    end
    render json: [], status: 200
  end
end
