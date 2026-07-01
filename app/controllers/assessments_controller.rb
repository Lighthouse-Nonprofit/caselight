class AssessmentsController < AdminController
  include AccessAudit   # AU-2/AU-12: audit successful Assessment show/index reads
  include SensitiveFields   # Phase 5.3 — visible_domain_levels
  load_and_authorize_resource

  before_action :find_client
  before_action :find_assessment, only: [:edit, :update, :show, :download_attachment]
  before_action :restrict_invalid_assessment, only: [:new, :create]
  before_action :restrict_update_assessment, only: [:edit, :update]

  def index
  end

  def new
    @assessment = @client.assessments.new
    @assessment.populate_notes
  end

  def create
    @assessment = @client.assessments.new(assessment_params)
    if @assessment.save
      redirect_to client_assessment_path(@client, @assessment), notice: t('.successfully_created')
    else
      render :new
    end
  end

  def show
    # Phase 5.3 — single source of truth for which Domain sensitivity levels this viewer may see.
    @visible_domain_levels = visible_domain_levels
  end

  # Phase 5.3 (NIST AC-6) — authenticated, sensitivity-gated download for assessment_domain
  # attachments. CanCan authorizes via alias_action(:download_attachment => :read) + find_client
  # (accessible_by) so record-auth holds; this layers the domain-sensitivity (field) check, which on
  # denial emits the STATIC 403 (NOT a redirect). The static /uploads path is separately denied by
  # UploadsStaticGuard, so this controller is the only serve path.
  def download_attachment
    assessment_domain = @assessment.assessment_domains.find(params[:assessment_domain_id])
    index  = params[:index].to_i
    levels = visible_domain_levels
    unless assessment_domain.domain && levels.include?(assessment_domain.domain.sensitivity)
      AccessLog.security_event!(
        event_type: 'sensitive_field_denied',
        request:    request,
        user:       current_user,
        metadata: {
          'surface'           => 'assessment_domain_attachment',
          'assessment_id'     => @assessment.id,
          'client_id'         => @client.id,
          'domain_id'         => assessment_domain.domain_id,
          'sensitivity_level' => assessment_domain.domain.try(:sensitivity)
        }
      )
      return render template: 'errors/403', status: :forbidden, layout: false
    end
    attachment = assessment_domain.attachments[index]
    return render plain: 'Not found', status: :not_found, layout: false if attachment.nil? || attachment.file.nil?
    send_file attachment.file.path, filename: File.basename(attachment.file.path), disposition: 'attachment'
  rescue ActiveRecord::RecordNotFound
    render plain: 'Not found', status: :not_found, layout: false
  rescue => e
    Rails.logger.error("[assessments#download_attachment] failing closed: #{e.class}: #{e.message}")
    render template: 'errors/403', status: :forbidden, layout: false
  end

  def edit
  end

  def update
    params[:assessment][:assessment_domains_attributes].each do |assessment_domain|
      add_more_attachments(assessment_domain.second[:attachments], assessment_domain.second[:id])
    end
    if @assessment.update(assessment_params)
      @assessment.update(updated_at: DateTime.now)
      @assessment.assessment_domains.update_all(assessment_id: @assessment.id)
      redirect_to client_assessment_path(@client, @assessment), notice: t('.successfully_updated')
    else
      render :edit
    end
  end

  def destroy
    if params[:file_index].present?
      remove_attachment_at_index(params[:file_index].to_i)
      message ||= t('.successfully_deleted')
      respond_to do |f|
        f.json { render json: { message: message }, status: '200' }
      end
    end
  end

  private

  def find_client
    @client = Client.accessible_by(current_ability).friendly.find(params[:client_id])
  end

  def find_assessment
    @assessment = @client.assessments.find(params[:id])
  end

  def assessment_params
    # params.require(:assessment).permit(assessment_domains_attributes: [:id, :domain_id, :score, :reason, :goal])

    default_params = params.require(:assessment).permit(assessment_domains_attributes: [:id, :domain_id, :score, :reason, :goal])
    default_params = params.require(:assessment).permit(assessment_domains_attributes: [:id, :domain_id, :score, :reason, :goal, attachments: []]) if action_name == 'create'
    default_params
  end

  def restrict_invalid_assessment
    redirect_to client_assessments_path(@client) unless @client.can_create_assessment?
  end

  def restrict_update_assessment
    redirect_to client_assessments_path(@client) unless @assessment.latest_record?
  end

  def remove_attachment_at_index(index)
    assessment_domain = AssessmentDomain.find(params[:assessment_domain])
    remain_attachment = assessment_domain.attachments
    deleted_attachment = remain_attachment.delete_at(index)
    deleted_attachment.try(:remove!)
    remain_attachment.empty? ? assessment_domain.remove_attachments! : (assessment_domain.attachments = remain_attachment )
    message = t('.fail_delete_attachment') unless assessment_domain.save
  end

  def add_more_attachments(new_file, assessment_domain_id)
    if new_file.present?
      assessment_domain = AssessmentDomain.find(assessment_domain_id)
      files = assessment_domain.attachments
      files += new_file
      assessment_domain.attachments = files
      assessment_domain.save
    end
  end
end
