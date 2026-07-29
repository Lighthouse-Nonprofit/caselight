class ClientEnrollmentTrackingsController < AdminController
  load_and_authorize_resource

  include ClientEnrollmentTrackingsConcern
  include SensitiveFields   # the client hub header (rendered on these pages now) reads the visible set
  include FormBuilderAttachments

  # Investor UX round (2026-07): new/create PORTED from the retired legacy controller
  # (ClientEnrolledProgramTrackingsController) — this family never had them, so tracking
  # creation only worked through the legacy pages. index/report died with the TrackingGrid
  # page: trackings render inside the Programs tab's per-program pane, and every redirect
  # lands on that pane's deep link.

  def new
    @client_enrollment_tracking = @enrollment.client_enrollment_trackings.new
    @attachment = @client_enrollment_tracking.form_builder_attachments.build
    authorize @client_enrollment_tracking
  end

  def create
    @client_enrollment_tracking = @enrollment.client_enrollment_trackings.new(client_enrollment_tracking_params)
    authorize @client_enrollment_tracking

    if @client_enrollment_tracking.save
      redirect_to client_client_enrollments_path(@client, program_stream_id: @program_stream.id), notice: t('.successfully_created')
    else
      render :new
    end
  end

  def edit
    authorize @client_enrollment_tracking
  end

  def update
    authorize @client_enrollment_tracking
    if @client_enrollment_tracking.update(client_enrollment_tracking_params)
      add_more_attachments(@client_enrollment_tracking)
      redirect_to client_client_enrollments_path(@client, program_stream_id: @program_stream.id), notice: t('.successfully_updated')
    else
      render :edit
    end
  end

  def show
  end

  def destroy
    name = params[:file_name]
    index = params[:file_index].to_i
    if name.present? && index.present?
      delete_form_builder_attachment(@client_enrollment_tracking, name, index)
      redirect_to request.referer, notice: t('.delete_attachment_successfully')
    else
      @client_enrollment_tracking.destroy
      redirect_to client_client_enrollments_path(@client, program_stream_id: @program_stream.id), notice: t('.successfully_deleted')
    end
  end
end
