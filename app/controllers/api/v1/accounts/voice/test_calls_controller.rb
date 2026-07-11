class Api::V1::Accounts::Voice::TestCallsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_admin_authorization?
  before_action :ensure_voice_ai_enabled

  def create
    inbox = Current.account.inboxes.find(params.require(:inbox_id))
    voice_agent = Current.account.voice_agents.find(params.require(:voice_agent_id))
    call = Voice::TestCallBuilder.perform!(
      account: Current.account,
      inbox: inbox,
      voice_agent: voice_agent,
      caller_name: params[:caller_name],
      caller_number: params[:caller_number],
      initiated_by: Current.user
    )
    render json: Voice::CallSerializer.new(call).payload, status: :created
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue AiImprovements::Usage::Exhausted => e
    render_ai_improvement_credits_exhausted(e)
  end
end
