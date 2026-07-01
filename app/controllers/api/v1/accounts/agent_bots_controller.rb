class Api::V1::Accounts::AgentBotsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :agent_bot, except: [:index, :create]
  before_action :validate_bot_type!, only: [:create, :update]

  def index
    @agent_bots = AgentBot.webhook_accessible_to(Current.account)
  end

  def show; end

  def create
    @agent_bot = Current.account.agent_bots.create!(permitted_params.except(:avatar_url, :bot_type).merge(bot_type: :webhook))
    process_avatar_from_url
  end

  def update
    @agent_bot.update!(permitted_params.except(:avatar_url, :bot_type))
    process_avatar_from_url
  end

  def avatar
    @agent_bot.avatar.purge if @agent_bot.avatar.attached?
    @agent_bot
  end

  def destroy
    @agent_bot.destroy!
    head :ok
  end

  def reset_access_token
    @agent_bot.access_token.regenerate_token
    @agent_bot.reload
  end

  def reset_secret
    @agent_bot.reset_secret!
  end

  private

  def agent_bot
    @agent_bot = AgentBot.webhook_accessible_to(Current.account).find(params[:id]) if params[:action] == 'show'
    @agent_bot ||= Current.account.agent_bots.webhook.find(params[:id])
  end

  def permitted_params
    params.permit(:name, :description, :outgoing_url, :avatar, :avatar_url, :bot_type, bot_config: {})
  end

  def validate_bot_type!
    return if permitted_params[:bot_type].blank? || permitted_params[:bot_type] == 'webhook'

    render json: { error: 'bot_type must be webhook' }, status: :unprocessable_entity
  end

  def process_avatar_from_url
    ::Avatar::AvatarFromUrlJob.perform_later(@agent_bot, params[:avatar_url]) if params[:avatar_url].present?
  end
end
