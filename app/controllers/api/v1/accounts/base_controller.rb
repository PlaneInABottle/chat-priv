class Api::V1::Accounts::BaseController < Api::BaseController
  include SwitchLocale
  include EnsureCurrentAccountHelper
  before_action :current_account
  before_action :validate_token_api_access, if: :authenticate_by_access_token?
  around_action :switch_locale_using_account_locale

  private

  def validate_token_api_access
    return if Current.account.api_and_webhooks_enabled?

    render json: { error: 'API access is not enabled for this account' }, status: :forbidden
  end

  def ensure_ai_agent_enabled
    return if Current.account.ai_agent_enabled?

    render json: { error: 'AI Agent is not enabled for this account' }, status: :forbidden
  end

  def ensure_voice_ai_enabled
    return if Current.account.voice_ai_enabled?

    render json: { error: 'Voice AI is disabled for this account.' }, status: :forbidden
  end
end
