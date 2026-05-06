class Api::V1::Accounts::AiAgentsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :set_ai_agent, only: [:show, :update, :destroy]

  def index
    @ai_agents = Current.account.ai_agents.includes(agent_bot: :inboxes).order(:created_at)
  end

  def show
    load_available_inboxes
  end

  def create
    @ai_agent = Current.account.ai_agents.build(ai_agent_params)
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
    @ai_agent.assign_attributes(ai_agent_params)
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

  private

  def set_ai_agent
    @ai_agent = Current.account.ai_agents.includes(agent_bot: :inboxes).find(params[:id])
  end

  def ai_agent_params
    params.permit(:name, :prompt, :enabled)
  end

  def inbox_ids_param
    Array(params[:inbox_ids]).map(&:to_i).select(&:positive?)
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
end
