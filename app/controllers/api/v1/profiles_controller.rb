class Api::V1::ProfilesController < Api::BaseController
  before_action :set_user

  def show; end

  def update
    if password_params[:password].present?
      render_could_not_create_error('Invalid current password') and return unless @user.valid_password?(password_params[:current_password])

      @user.update!(password_params.except(:current_password))
    end

    @user.assign_attributes(profile_update_params)
    @user.custom_attributes.merge!(custom_attributes_params)
    @user.save!
  end

  def avatar
    @user.avatar.attachment.destroy! if @user.avatar.attached?
    @user.reload
  end

  def auto_offline
    current_account_user.update!(auto_offline: auto_offline_params[:auto_offline] || false)
  end

  def availability
    current_account_user.update!(availability: availability_params[:availability])
  end

  def set_active_account
    current_account_user.update!(active_at: Time.current)
    head :ok
  end

  def resend_confirmation
    @user.send_confirmation_instructions unless @user.confirmed?
    head :ok
  end

  def reset_access_token
    @user.access_token.regenerate_token
    @user.reload
  end

  private

  def set_user
    @user = current_user
  end

  def availability_params
    params.require(:profile).permit(:availability)
  end

  def auto_offline_params
    params.require(:profile).permit(:auto_offline)
  end

  def profile_update_params
    params.require(:profile).permit(
      :email,
      :name,
      :display_name,
      :avatar,
      :message_signature,
      ui_settings: {}
    )
  end

  def current_account_user
    @current_account_user ||= @user.account_users.find_by!(account_id: requested_account_id)
  end

  def requested_account_id
    Integer(params.require(:profile)[:account_id], exception: false)
  end

  def custom_attributes_params
    params.require(:profile).permit(:phone_number)
  end

  def password_params
    params.require(:profile).permit(
      :current_password,
      :password,
      :password_confirmation
    )
  end
end
