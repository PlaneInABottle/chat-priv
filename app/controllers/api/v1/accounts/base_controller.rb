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

  def ensure_ai_improvement_credits!(operation:, ai_agent: nil, voice_agent: nil)
    AiImprovements::Usage::Limiter.new(
      account: Current.account,
      operation: operation,
      ai_agent: ai_agent,
      voice_agent: voice_agent,
      initiated_by: Current.user
    ).ensure_available!
  end

  def render_ai_improvement_credits_exhausted(error)
    render json: {
      error: error.message,
      code: 'ai_improvement_credits_exhausted',
      usage: error.summary
    }, status: :payment_required
  end
end
