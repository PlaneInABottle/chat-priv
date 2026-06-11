class Api::V1::Accounts::Voice::AgentsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_admin_authorization?
  before_action :set_voice_agent, only: [:show, :update, :destroy]

  def index
    voice_agents = Current.account.voice_agents.order(:created_at)
    render json: { payload: voice_agents.map { |agent| VoiceAgents::Serializer.new(agent).payload } }
  end

  def show
    render json: VoiceAgents::Serializer.new(@voice_agent).payload
  end

  def create
    voice_agent = Current.account.voice_agents.create!(voice_agent_params)
    render json: VoiceAgents::Serializer.new(voice_agent).payload, status: :created
  end

  def update
    @voice_agent.update!(voice_agent_params)
    render json: VoiceAgents::Serializer.new(@voice_agent).payload
  end

  def destroy
    @voice_agent.destroy!
    head :no_content
  end

  private

  def set_voice_agent
    @voice_agent = Current.account.voice_agents.find(params[:id])
  end

  def voice_agent_params
    permitted = params.permit(:name, :enabled, :greeting, :prompt, tools_config: {})
    normalize_voice_agent_params(permitted.to_h.deep_stringify_keys)
  end

  def normalize_voice_agent_params(permitted)
    return permitted unless permitted.key?('tools_config')

    permitted.merge('tools_config' => VoiceAgents::Config.new(permitted['tools_config']).normalized_config)
  end
end
