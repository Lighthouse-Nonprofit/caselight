class UsersController < AdminController
  include SensitiveFields  # Phase 5.3
  load_and_authorize_resource

  before_action :find_user, only: [:show, :edit, :update, :destroy]
  before_action :find_association, except: [:index, :destroy]

  def index
    @user_grid = UserGrid.new(sanitized_grid_order(UserGrid, params[:user_grid]))
    respond_to do |f|
      f.html do
        @results = @user_grid.scope { |scope| scope.accessible_by(current_ability) }.assets.size
        @user_grid.scope { |scope| scope.accessible_by(current_ability).page(params[:page]).per(20) }
      end
      f.xls do
        # Phase 6 (U1): the export must honor the same ability scope as the HTML branch —
        # without this the XLS emitted the full UserGrid scope regardless of viewer.
        @user_grid.scope { |scope| scope.accessible_by(current_ability) }
        send_data @user_grid.to_xls, filename: "user_report-#{Time.now}.xls"
      end
    end
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to @user, notice: t('.successfully_created')
    else
      render :new
    end
  end

  def show
    custom_field_ids          = @user.custom_field_properties.pluck(:custom_field_id)
    visible = visible_custom_field_ids_for(@user)
    # Phase 5.3 — mask UNFILLED user-form titles too (consistency with clients/families/partners);
    # closes the staff-record form-title metadata leak. No break-glass for User (grants are
    # Client/Family/Partner-scoped), so emergency_only user forms stay masked for all.
    @free_user_forms          = CustomField.user_forms.not_used_forms(custom_field_ids).where(id: visible.to_a).order_by_form_title
    @group_user_custom_fields = @user.custom_field_properties
                                     .where(custom_field_id: visible.to_a)
                                     .group_by(&:custom_field_id)

    @client_grid = ClientGrid.new(params.fetch(:client_grid, {}).merge!(current_user: @user))
    # Phase 5.3 — mask the embedded grid to the CURRENT VIEWER (current_user), NOT @user. respond_to?
    # guard keeps this order-independent of the client_grid.rb attr_accessor edit.
    @client_grid.visible_custom_field_ids = visible_custom_field_ids if @client_grid.respond_to?(:visible_custom_field_ids=)
    @results     = @client_grid.scope { |scope| scope.of_case_worker(@user.id) }.assets.size

    @client_grid.scope do |scope|
      scope.of_case_worker(@user.id).page(params[:page]).per(10)
    end
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to @user, notice: t('.successfully_updated')
    else
      render :edit
    end
  end

  def destroy
    if @user.no_any_associated_objects?
      @user.destroy
      AccessLog.record_destroyed!(self, @user)  # Phase 6 (AU-2), values-free
      redirect_to users_url, notice: t('.successfully_deleted')
    else
      redirect_to users_url, alert: t('.alert')
    end
  end

  def version
    page = params[:per_page] || 20
    @user     = User.find(params[:user_id])
    @versions = @user.versions.reorder(created_at: :desc).page(params[:page]).per(page)
  end

  def disable
    @user = User.find(params[:user_id])
    redirect_to users_path, notice: t('.successfully_disable') if @user.update(disable: !@user.disable)
  end

  # Admin: clear a Devise lockout (AC-7) so the user can sign in again.
  def unlock
    @user = User.find(params[:user_id])
    @user.unlock_access!
    redirect_to user_path(@user), notice: t('.unlocked', default: 'Account unlocked — the user can sign in again.')
  end

  # Admin: reset another user's password to a strong temporary one. No reset EMAIL is sent (SMTP is
  # not wired for the pilot), so the temp password is shown ONCE to the admin to hand off securely;
  # it is force-expired so the user must change it at next sign-in.
  def reset_password
    @user = User.find(params[:user_id])
    temp = "#{SecureRandom.alphanumeric(14)}A9!"
    if @user.update(password: temp, password_confirmation: temp)
      @user.unlock_access! if @user.respond_to?(:access_locked?) && @user.access_locked?
      @user.update_column(:password_changed_at, 1.year.ago) if @user.respond_to?(:password_changed_at)
      redirect_to user_path(@user),
                  notice: t('.password_reset', default: 'Temporary password (share securely; the user must change it at next sign-in): %{pw}', pw: temp)
    else
      redirect_to user_path(@user), alert: @user.errors.full_messages.to_sentence
    end
  end

  private

  def user_params
    params.require(:user).permit(:first_name, :last_name, :roles, :start_date,
                                :job_title, :mobile, :date_of_birth,
                                :province_id, :email, :password,:password_confirmation,
                                :manager_id, :calendar_integration, :pin_number, custom_field_ids: [])
  end

  def find_user
    @user = User.find(params[:id])
  end

  def find_association
    # D2: @department dropped — Departments hidden for the pilot (form input removed)
    @province   = Province.order(:name)
    @managers   = User.managers.order(:first_name, :last_name)
    @managers   = @managers.where.not(id: params[:id]) if params[:action] == 'edit' || params[:action] == 'update'
  end
end
