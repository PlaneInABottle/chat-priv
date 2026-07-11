class Api::V1::Accounts::AiAgentsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :ensure_ai_agent_enabled
  before_action :set_ai_agent, only: [:show, :update, :destroy, :publish, :pause]

  def index
    @ai_agents = Current.account.ai_agents.includes(:current_release, agent_bot: :inboxes).order(:created_at)
  end

  def show
    load_available_inboxes
  end

  def create
    @ai_agent = Current.account.ai_agents.build(merged_ai_agent_params)
    @ai_agent.enabled = false
    @ai_agent.inbox_ids = inbox_ids_param if params.key?(:inbox_ids)

    if @ai_agent.save
      sync_inbox_bindings if params.key?(:inbox_ids)
      load_available_inboxes
      render :show
    else
      render json: { errors: @ai_agent.errors }, status: :unprocessable_entity
    end
  end

  def update
    @ai_agent.assign_attributes(merged_ai_agent_params)
    @ai_agent.inbox_ids = inbox_ids_param if params.key?(:inbox_ids)

    if @ai_agent.save
      @ai_agent.agent_bot&.update!(name: @ai_agent.name)
      sync_inbox_bindings if params.key?(:inbox_ids)
      load_available_inboxes
      render :show
    else
      render json: { errors: @ai_agent.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    @ai_agent.destroy!
    head :no_content
  end

  def publish
    return render_readiness_error unless @ai_agent.readiness[:can_publish]

    @ai_agent.publish!(created_by: Current.user)
    load_available_inboxes
    render :show
  end

  def pause
    @ai_agent.pause!
    load_available_inboxes
    render :show
  end

  private

  def set_ai_agent
    @ai_agent = Current.account.ai_agents.includes(:current_release, agent_bot: :inboxes).find(params[:id])
  end

  def ai_agent_params
    params.permit(:name, :prompt, config: {})
  end

  def inbox_ids_param
    Array(params[:inbox_ids]).map(&:to_i).select(&:positive?)
  end

  def merged_ai_agent_params
    permitted = ai_agent_params.to_h.deep_stringify_keys
    return permitted unless permitted.key?('config')

    merged_config = existing_config.deep_merge(permitted['config'] || {})
    if merged_config.key?('tools')
      merged_config['tools'] = tool_availability.filter_tools_config(
        merged_config['tools'],
        AiAgents::ToolRegistry.available_definitions
      )
    end

    if merged_config.key?('instructions')
      instruction_document = AiAgents::InstructionDocument.new(merged_config['instructions'])
      merged_config['instructions'] = instruction_document.normalized
      permitted['prompt'] = instruction_document.compile
    end

    permitted.merge('config' => merged_config)
  end

  def tool_availability
    @tool_availability ||= AiAgents::ToolAvailability.new(account: Current.account)
  end

  def existing_config
    @ai_agent&.config.is_a?(Hash) ? @ai_agent.config.deep_stringify_keys : {}
  end

  def sync_inbox_bindings
    bot = @ai_agent.agent_bot
    return true unless bot

    target_ids = inbox_ids_param.uniq

    # Clear existing bindings for this bot
    bot.agent_bot_inboxes.destroy_all

    # Create new bindings
    target_ids.each do |inbox_id|
      inbox = Current.account.inboxes.find_by(id: inbox_id)
      next unless inbox

      AgentBotInbox.create!(agent_bot: bot, inbox: inbox, account: Current.account)
    end

    bot.update!(name: @ai_agent.name)
    @ai_agent.reload
    true
  end

  def load_available_inboxes
    @available_inboxes = Current.account.inboxes.includes(:channel, agent_bot: :ai_agent).order_by_name
  end

  def render_readiness_error
    render json: { error: 'Complete the required setup before publishing.', readiness: @ai_agent.readiness }, status: :unprocessable_entity
  end
end
