class ClientEnrollmentsController < AdminController
  load_and_authorize_resource

  include ClientEnrollmentConcern
  include SensitiveFields   # UX rung 4 — the client hub header's Forms dropdown reads the visible set
  include FormBuilderAttachments

  def index
    # Investor UX round (2026-07): one sub-tab per ever-enrolled program — active first, then
    # exited (`.complete` deliberately dropped on the pane scopes so Overview deep links always
    # resolve, even for incompletely-configured streams) — plus an Add Program picker modal
    # holding the never-enrolled list (exited programs re-enroll from their own pane).
    @active_streams  = ProgramStreamDecorator.decorate_collection(ProgramStream.active_enrollments(@client))
    @exited_streams  = ProgramStreamDecorator.decorate_collection(ProgramStream.inactive_enrollments(@client))
    @pane_streams    = @active_streams + @exited_streams
    # OCA 2026-08-26: legacy/Casebook-era programs are retired by setting lifecycle status
    # `completed`. Until now `lifecycle_active` had ZERO call sites, so a "completed" program kept
    # appearing in the picker and kept accepting enrollments -- the status only changed a badge.
    @enrollable_streams = ProgramStreamDecorator.decorate_collection(
      ProgramStream.without_status_by(@client).complete.lifecycle_active
    )
    @enrollments_by_stream = @client.client_enrollments
                                    .where(program_stream_id: @pane_streams.map(&:id))
                                    .includes(:leave_program, client_enrollment_trackings: :tracking)
                                    .order(created_at: :desc)
                                    .group_by(&:program_stream_id)
    requested = params[:program_stream_id].presence&.to_i
    @selected_stream_id = @pane_streams.map(&:id).include?(requested) ? requested : @pane_streams.first&.id
  end

  def new
    if @program_stream.has_rule?
      if @program_stream.has_program_exclusive? || @program_stream.has_mutual_dependence?
        client_enrollment_index_path unless valid_client? && valid_program?
      else
        client_enrollment_index_path unless valid_client?
      end
    elsif @program_stream.has_program_exclusive? || @program_stream.has_mutual_dependence?
      client_enrollment_index_path unless valid_program?
    end

    @client_enrollment = @client.client_enrollments.new(program_stream_id: @program_stream)
    @attachment        = @client_enrollment.form_builder_attachments.build
  end

  def edit
  end

  def update
    if @client_enrollment.update(client_enrollment_params)
      add_more_attachments(@client_enrollment)
      redirect_to client_client_enrollment_path(@client, @client_enrollment, program_stream_id: @program_stream), notice: t('.successfully_updated')
    else
      render :edit
    end
  end

  def show
  end

  def create
    @client_enrollment = @client.client_enrollments.new(client_enrollment_params)
    authorize @client_enrollment
    if @client_enrollment.save
      # Investor UX round (2026-07): land on the new program's pane (this used to cross-wire
      # into the legacy client_enrolled_programs family).
      redirect_to client_client_enrollments_path(@client, program_stream_id: @program_stream.id), notice: t('.successfully_created')
    else
      render :new
    end
  end

  def destroy
    name = params[:file_name]
    index = params[:file_index].to_i
    params_program_streams = params[:program_streams]
    if name.present? && index.present?
      delete_form_builder_attachment(@client_enrollment, name, index)
      redirect_to request.referer, notice: t('.delete_attachment_successfully')
    else
      @client_enrollment.destroy
      redirect_to client_client_enrollments_path(@client, program_stream_id: @program_stream.id), notice: t('.successfully_deleted')
    end
  end

  def report
    # Investor UX round (2026-07): the standalone report page folded into the Programs tab's
    # per-program pane — permanent redirect keeps old bookmarks and back-links working.
    redirect_to client_client_enrollments_path(@client, program_stream_id: params[:program_stream_id]), status: :moved_permanently
  end
end
