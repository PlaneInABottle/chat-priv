class Api::V1::Accounts::AiAgentsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :set_ai_agent

  def show; end

  def simulate
    messages = params[:messages] || []
    service = AiAgents::ResponseService.new(ai_agent: @ai_agent, messages: messages)
    response_text = service.perform

    if response_text
      render json: { response: response_text }
    else
      render json: { error: 'Failed to generate response' }, status: :unprocessable_entity
    end
  end

  def update
    @ai_agent.assign_attributes(ai_agent_params)
    validate_inbox_presence! if @ai_agent.enabled? && ai_agent_params[:enabled].nil?
    validate_inbox_presence! if ai_agent_params[:enabled] == true

    @ai_agent.save!
    sync_inbox_bindings if params.key?(:inbox_ids)
  end

  private

  def set_ai_agent
    @ai_agent = Current.account.ai_agent || Current.account.create_ai_agent
  end

  def ai_agent_params
    params.permit(:prompt, :enabled, config: {})
  end

  def validate_inbox_presence!
    return if params.key?(:inbox_ids) && inbox_ids_param.any?

    bot = @ai_agent.agent_bot
    return if bot&.inboxes&.any?

    @ai_agent.errors.add(:inbox_ids, 'must be present when enabling AI agent')
    raise ActiveRecord::RecordInvalid, @ai_agent
  end

  def inbox_ids_param
    Array(params[:inbox_ids]).map(&:to_i).select(&:positive?)
  end

  def sync_inbox_bindings
    bot = @ai_agent.agent_bot
    return unless bot

    target_ids = inbox_ids_param
    current_ids = bot.inboxes.pluck(:id)

    (current_ids - target_ids).each do |inbox_id|
      bot.agent_bot_inboxes.where(inbox_id: inbox_id).destroy_all
    end

    (target_ids - current_ids).each do |inbox_id|
      inbox = Current.account.inboxes.find_by(id: inbox_id)
      next unless inbox

      AgentBotInbox.create!(agent_bot: bot, inbox: inbox, account: Current.account)
    end
  end
end
