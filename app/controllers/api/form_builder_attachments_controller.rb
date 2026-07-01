module Api
  class FormBuilderAttachmentsController < AdminController
    before_action :find_attachment

    # Phase 5.6 (AC-3): this was a DESTRUCTIVE default-open hole -- it deleted a file off ANY
    # FormBuilderAttachment (found by id + name) with no ownership/authz. Authorize against the PARENT
    # form-buildable record the role actually edits (CustomFieldProperty / ClientEnrollment /
    # ClientEnrollmentTracking / LeaveProgram) -- NOT the bare CustomField class. This (a) keeps the
    # day-to-day case_worker working (they :manage those parent records), and (b) is record-scoped, so it
    # ACTUALLY closes the cross-caseload IDOR a class-level :manage CustomField would not. GATED behind
    # enforce_authorization? so flag-OFF is byte-identical (SHADOW-FIRST). Fail-closed if the parent is missing.
    def destroy
      if enforce_authorization?
        buildable = @attachment&.form_buildable
        raise CanCan::AccessDenied.new('Not authorized', :destroy, :form_builder_attachment) if buildable.nil?
        authorize! :update, buildable
      end
      index = params[:file_index].to_i
      remain_file  = @attachment.file
      deleted_file = remain_file.delete_at(index)
      deleted_file.try(:remove!)
      remain_file.empty? ? @attachment.remove_file! : @attachment.file = remain_file
      @attachment.save
      message ||= t('.successfully_deleted')
      respond_to do |f|
        f.json { render json: { message: message }, status: '200' }
      end
    end

    private

    def find_attachment
      id = params[:id]
      name = params[:file_name]
      @attachment = FormBuilderAttachment.find_by(id: id, name: name)
    end
  end
end
