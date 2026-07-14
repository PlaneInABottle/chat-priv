class Platform::Api::V1::AccountUsersController < PlatformController
  before_action :set_resource
  before_action :validate_platform_app_permissible

  def index
    render json: @resource.account_users
  end

  def create
    @account_user = @resource.account_users.find_or_initialize_by(user_id: account_user_params[:user_id])
    @account_user.role = requested_role if requested_role
    @account_user.save!
    render json: @account_user
  end

  def destroy
    @resource.account_users.find_by(user_id: account_user_params[:user_id])&.destroy!
    head :ok
  end

  private

  def set_resource
    @resource = Account.find(params[:account_id])
  end

  def account_user_params
    params.permit(:user_id)
  end

  def requested_role
    role = params[:role]
    return if role.blank?
    return role if AccountUser.roles.key?(role)

    raise ActionController::BadRequest, 'Invalid account user role'
  end
end
