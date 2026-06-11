class Api::V1::Accounts::Voice::TestCallsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_admin_authorization?

  def create
    inbox = Current.account.inboxes.find(params.require(:inbox_id))
    sync_voice_agent!(inbox)
    call = Voice::TestCallBuilder.perform!(
      account: Current.account,
      inbox: inbox,
      caller_name: params[:caller_name],
      caller_number: params[:caller_number],
      initiated_by: Current.user
    )
    render json: Voice::CallSerializer.new(call).payload, status: :created
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def sync_voice_agent!(inbox)
    return if params[:voice_agent_id].blank?

    voice_agent = Current.account.voice_agents.find(params[:voice_agent_id])
    setting = Current.account.voice_inbox_settings.find_or_initialize_by(inbox: inbox)
    setting.status ||= 'test_only'
    setting.voice_agent = voice_agent
    setting.save!
  end
end
