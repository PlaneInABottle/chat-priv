class Api::V1::Accounts::BaseController < Api::BaseController
  include SwitchLocale
  include EnsureCurrentAccountHelper
  before_action :current_account
  around_action :switch_locale_using_account_locale

  private

  def ensure_ai_agent_enabled
    return if Current.account.ai_agent_enabled?

    render json: { error: 'AI Agent is not enabled for this account' }, status: :forbidden
  end

  def ensure_voice_ai_enabled
    return if Current.account.voice_ai_enabled?

    render json: { error: 'Voice AI is disabled for this account.' }, status: :forbidden
  end
end
