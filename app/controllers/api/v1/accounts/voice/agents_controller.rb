class Api::V1::Accounts::Voice::AgentsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_admin_authorization?
  before_action :ensure_voice_ai_enabled
  before_action :set_voice_agent, only: [:show, :update, :destroy]

  def index
    voice_agents = Current.account.voice_agents.order(:created_at)
    render json: { payload: voice_agents.map { |agent| VoiceAgents::Serializer.new(agent).payload } }
  end

  def show
    render json: VoiceAgents::Serializer.new(@voice_agent).payload
  end

  def create
    voice_agent = Current.account.voice_agents.new(voice_agent_params)
    ActiveRecord::Base.transaction do
      voice_agent.save!
      sync_inbox_assignments!(voice_agent) if inbox_settings_provided?
    end
    render json: VoiceAgents::Serializer.new(voice_agent).payload, status: :created
  end

  def update
    ActiveRecord::Base.transaction do
      @voice_agent.update!(voice_agent_params)
      sync_inbox_assignments!(@voice_agent) if inbox_settings_provided?
    end
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
    permitted = voice_agent_request_params.except('inbox_settings')
    normalize_voice_agent_params(permitted.to_h.deep_stringify_keys)
  end

  def voice_agent_request_params
    @voice_agent_request_params ||= params.permit(
      :name,
      :enabled,
      :greeting,
      :prompt,
      tools_config: {},
      inbox_settings: [
        :id,
        :inbox_id,
        :fallback_team_id,
        :recording_enabled,
        { settings: {} }
      ]
    ).to_h.deep_stringify_keys
  end

  def normalize_voice_agent_params(permitted)
    return permitted unless permitted.key?('tools_config')

    normalized_tools_config = VoiceAgents::Config.new(permitted['tools_config']).normalized_config
    permitted.merge(
      'tools_config' => tool_availability.filter_tools_config(
        normalized_tools_config,
        VoiceAgents::ToolRegistry.available_definitions
      )
    )
  end

  def tool_availability
    @tool_availability ||= AiAgents::ToolAvailability.new(account: Current.account)
  end

  def inbox_settings_provided?
    voice_agent_request_params.key?('inbox_settings')
  end

  def sync_inbox_assignments!(voice_agent)
    kept_setting_ids = inbox_settings_params.map do |assignment|
      sync_inbox_assignment!(voice_agent, assignment)
    end

    voice_agent.voice_inbox_settings.where.not(id: kept_setting_ids).destroy_all
  end

  def inbox_settings_params
    Array.wrap(voice_agent_request_params['inbox_settings'])
  end

  def sync_inbox_assignment!(voice_agent, assignment)
    inbox = Current.account.inboxes.find(assignment['inbox_id'])
    setting = Current.account.voice_inbox_settings.find_or_initialize_by(inbox: inbox)
    setting.voice_agent = voice_agent
    setting.fallback_team_id = assignment['fallback_team_id'].presence
    if assignment.key?('recording_enabled')
      setting.recording_enabled = ActiveModel::Type::Boolean.new.cast(assignment['recording_enabled'])
    end
    setting.settings = assignment['settings'] if assignment['settings'].is_a?(Hash)
    setting.save!
    setting.id
  end
end
