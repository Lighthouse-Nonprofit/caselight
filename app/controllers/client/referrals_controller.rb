# PR 4 — referrals OUT, the per-client hub section. Mirrors Client::TasksController: a broad
# `can :manage, Referral` authorizes the action; find_client's accessible_by is what bounds the
# records to the viewer's caseload (a worker can only reach referrals on clients they can read).
class Client::ReferralsController < AdminController
  include SensitiveFields   # the client hub header's Forms chip reads visible_custom_field_ids_for
  load_and_authorize_resource
  before_action :find_client
  before_action :find_referral, only: [:edit, :update, :destroy]

  def index
    @referrals = @client.referrals.recent
  end

  def new
    @referral = @client.referrals.new(referred_on: Time.zone.today)
  end

  def create
    @referral = @client.referrals.new(referral_params)
    @referral.user ||= current_user
    if @referral.save
      redirect_to client_referrals_path(@client), notice: t('.successfully_created', default: 'Referral recorded.')
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @referral.update(referral_params)
      redirect_to client_referrals_path(@client), notice: t('.successfully_updated', default: 'Referral updated.')
    else
      render :edit
    end
  end

  def destroy
    @referral.destroy
    redirect_to client_referrals_path(@client), notice: t('.successfully_deleted', default: 'Referral removed.')
  end

  private

  def find_client
    @client = Client.accessible_by(current_ability).friendly.find(params[:client_id])
  end

  def find_referral
    @referral = @client.referrals.find(params[:id])
  end

  def referral_params
    params.require(:referral).permit(:organization_name, :referral_type, :contact_name,
                                     :contact_phone, :contact_email, :referred_on, :status,
                                     :outcome_on, :reason, :outcome, :user_id)
  end
end
