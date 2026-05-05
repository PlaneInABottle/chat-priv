class Api::V1::Accounts::AiAgentsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :set_ai_agent, only: [:show, :update, :destroy]

  def index
    @ai_agents = Current.account.ai_agents.includes(agent_bot: :inboxes)
  end

  def show; end

  def create
    @ai_agent = Current.account.ai_agents.build(ai_agent_params)

    if @ai_agent.save
      sync_inbox_bindings if params.key?(:inbox_ids)
      render :show
    else
      render json: { errors: @ai_agent.errors }, status: :unprocessable_entity
    end
  end

  def update
    @ai_agent.assign_attributes(ai_agent_params)

    if params.key?(:inbox_ids) && !sync_inbox_bindings
      render json: { errors: @ai_agent.errors }, status: :unprocessable_entity
      return
    end

    if @ai_agent.save
      @ai_agent.agent_bot&.update!(name: @ai_agent.name)
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
    @ai_agent = Current.account.ai_agents.find(params[:id])
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

    target_ids = inbox_ids_param

    # Check for conflicts with other AI agents
    conflicts = AgentBotInbox.joins(:agent_bot)
                             .where(agent_bots: { bot_type: :ai })
                             .where.not(agent_bot_id: bot.id)
                             .where(inbox_id: target_ids)
                             .exists?

    if conflicts
      @ai_agent.errors.add(:inbox_ids, 'already assigned to another AI agent')
      return false
    end

    # Clear existing bindings for this bot
    bot.agent_bot_inboxes.destroy_all

    # Create new bindings
    target_ids.each do |inbox_id|
      inbox = Current.account.inboxes.find_by(id: inbox_id)
      next unless inbox

      AgentBotInbox.create!(agent_bot: bot, inbox: inbox, account: Current.account)
    end

    bot.update!(name: @ai_agent.name)
    true
  end
end
