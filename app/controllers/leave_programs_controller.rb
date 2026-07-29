class LeaveProgramsController < AdminController
  load_and_authorize_resource

  include LeaveProgramsConcern
  include SensitiveFields   # the client hub header (rendered on these pages now) reads the visible set
  include FormBuilderAttachments

  # Investor UX round (2026-07): new/create PORTED from the retired legacy controller
  # (LeaveEnrolledProgramsController) — this family never had them, so exiting a program only
  # worked through the legacy pages. The concern's initial_attachments builds @leave_program
  # off @enrollment for new/create; create just assigns the params.

  def new
  end

  def create
    @leave_program.assign_attributes(leave_program_params)
    if @leave_program.save
      redirect_to client_client_enrollment_leave_program_path(@client, @enrollment, @leave_program), notice: t('.successfully_created')
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @leave_program.update(leave_program_params)
      add_more_attachments(@leave_program)
      redirect_to client_client_enrollment_leave_program_path(@client, @enrollment, @leave_program), notice: t('.successfully_updated')
    else
      render :edit
    end
  end

  def show
  end

  def destroy
    name = params[:file_name]
    index = params[:file_index].to_i
    params_program_streams = params[:program_streams]
    if name.present? && index.present?
      delete_form_builder_attachment(@leave_program, name, index)
    end
    redirect_to request.referer, notice: t('.delete_attachment_successfully')
  end
end
