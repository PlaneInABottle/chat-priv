class Api::V2::AccountsController < Api::BaseController
  include AuthHelper

  skip_before_action :authenticate_user!, :set_current_user, :handle_with_exception,
                     only: [:create], raise: false
  before_action :check_signup_enabled, only: [:create]
  before_action :validate_captcha, only: [:create]
  before_action :fetch_account, except: [:create]
  before_action :check_authorization, except: [:create]

  rescue_from CustomExceptions::Account::InvalidEmail,
              CustomExceptions::Account::UserExists,
              CustomExceptions::Account::UserErrors,
              with: :render_error_response

  def create
    confirmation_required = email_confirmation_required?
    @user, @account = AccountBuilder.new(
      account_name: account_params[:account_name],
      user_full_name: account_params[:user_full_name],
      email: account_params[:email],
      user_password: account_params[:password],
      locale: account_params[:locale],
      user: current_user,
      confirmed: !confirmation_required,
      ensure_valid: true,
      apply_freemium_limits: current_user.nil?
    ).perform

    fetch_account_and_user_info
    update_account_info if @account.present?

    if @user
      render_signup_response(confirmation_required)
    else
      render_error_response(CustomExceptions::Account::SignupFailed.new({}))
    end
  end

  private

  def account_attributes
    {
      custom_attributes: @account.custom_attributes.merge({ 'onboarding_step' => 'profile_update' })
    }
  end

  def update_account_info
    @account.update!(
      account_attributes
    )
  end

  def fetch_account_and_user_info; end

  def fetch_account
    @account = current_user.accounts.find(params[:id])
    @current_account_user = @account.account_users.find_by(user_id: current_user.id)
  end

  def account_params
    params.permit(:account_name, :email, :name, :password, :locale, :domain, :support_email, :user_full_name)
  end

  def check_signup_enabled
    raise ActionController::RoutingError, 'Not Found' unless GlobalConfigService.account_signup_enabled?
  end

  def api_only_signup?
    # CW_API_ONLY_SERVER is the canonical flag for API-only deployments.
    # ENABLE_ACCOUNT_SIGNUP='api_only' is a legacy sentinel for the same purpose.
    # Read ENABLE_ACCOUNT_SIGNUP raw from InstallationConfig because GlobalConfig.get
    # typecasts it to boolean, coercing 'api_only' to true.
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('CW_API_ONLY_SERVER', false)) ||
      InstallationConfig.find_by(name: 'ENABLE_ACCOUNT_SIGNUP')&.value.to_s == 'api_only'
  end

  def email_confirmation_required?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('REQUIRE_EMAIL_CONFIRMATION', 'true')) != false
  end

  def render_signup_response(confirmation_required)
    # Authenticated users, API-only signups, and confirmed web signups need
    # the full response with account_id and auth tokens. When confirmation is
    # required, unauthenticated web signup keeps the existing email-only flow.
    if current_user || api_only_signup? || !confirmation_required
      send_auth_headers(@user)
      render 'api/v1/accounts/create', format: :json, locals: { resource: @user }
    else
      render json: { email: @user.email }
    end
  end

  def validate_captcha
    raise ActionController::InvalidAuthenticityToken, 'Invalid Captcha' unless ChatwootCaptcha.new(params[:h_captcha_client_response]).valid?
  end
end

Api::V2::AccountsController.prepend_mod_with('Api::V2::AccountsController')
