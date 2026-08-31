class Api::V1::Accounts::Voice::AgentsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_admin_authorization?
  before_action :ensure_voice_ai_enabled
  before_action :set_voice_agent, only: [:show, :update, :destroy, :publish, :activate, :pause]

  def index
    voice_agents = Current.account.voice_agents.includes(:current_release, :knowledge_sources).order(:created_at)
    render json: { payload: voice_agents.map { |agent| VoiceAgents::Serializer.new(agent).payload } }
  end

  def show
    render json: VoiceAgents::Serializer.new(@voice_agent).payload
  end

  def create
    voice_agent = Current.account.voice_agents.new(VoiceAgents::RuntimeDefaults.attributes.merge(voice_agent_params))
    voice_agent.assign_attributes(instruction_attributes(voice_agent))
    voice_agent.enabled = false
    ActiveRecord::Base.transaction do
      voice_agent.save!
      sync_inbox_assignments!(voice_agent) if inbox_settings_provided?
      sync_knowledge_sources!(voice_agent) if knowledge_source_ids_provided?
    end
    render json: VoiceAgents::Serializer.new(voice_agent).payload, status: :created
  end

  def update
    attributes = voice_agent_params.merge(instruction_attributes(@voice_agent))
    ActiveRecord::Base.transaction do
      @voice_agent.assign_attributes(attributes)
      unless @voice_agent.last_tested_draft_fingerprint == @voice_agent.draft_fingerprint
        @voice_agent.last_tested_at = nil
        @voice_agent.last_tested_draft_fingerprint = nil
      end
      @voice_agent.save!
      sync_inbox_assignments!(@voice_agent) if inbox_settings_provided?
      sync_knowledge_sources!(@voice_agent) if knowledge_source_ids_provided?
    end
    render json: VoiceAgents::Serializer.new(@voice_agent).payload
  end

  def destroy
    @voice_agent.destroy!
    head :no_content
  end

  def publish
    return render_readiness_error unless @voice_agent.readiness[:can_publish]

    @voice_agent.publish!(created_by: Current.user, activate: publish_activation?)
    render json: VoiceAgents::Serializer.new(@voice_agent).payload
  end

  def activate
    return render json: { error: 'Publish the assistant before activation.' }, status: :unprocessable_content unless @voice_agent.current_release

    @voice_agent.activate!
    render json: VoiceAgents::Serializer.new(@voice_agent).payload
  end

  def pause
    @voice_agent.pause!
    render json: VoiceAgents::Serializer.new(@voice_agent).payload
  end

  private

  def publish_activation?
    return true unless params.key?(:activate)

    ActiveModel::Type::Boolean.new.cast(params[:activate])
  end

  def set_voice_agent
    @voice_agent = Current.account.voice_agents.includes(:current_release, :knowledge_sources).find(params[:id])
  end

  def voice_agent_params
    permitted = voice_agent_request_params.except('instructions', 'inbox_settings', 'knowledge_source_ids')
    normalize_voice_agent_params(permitted.to_h.deep_stringify_keys)
  end

  def voice_agent_request_params
    @voice_agent_request_params ||= params.permit(
      :name,
      :greeting,
      :prompt,
      instructions: {},
      knowledge_source_ids: [],
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

  def instruction_attributes(voice_agent = nil)
    prompt_provided = params.key?(:prompt)
    instructions_provided = params.key?(:instructions)
    return {} unless prompt_provided || instructions_provided

    reject_instruction_conflict!(voice_agent, prompt_provided, instructions_provided)
    return {} unless instructions_provided

    document = VoiceAgents::InstructionDocument.new(raw_instructions).validate_compiled_length!
    normalized = document.normalized
    current_config = voice_agent&.config.is_a?(Hash) ? voice_agent.config.deep_stringify_keys : {}
    {
      'prompt' => document.compile,
      'config' => current_config.except(VoiceAgent::LEGACY_AUTHORING_PROFILE_KEY).merge(VoiceAgent::INSTRUCTIONS_KEY => normalized)
    }
  rescue ArgumentError, KeyError => e
    invalid_instructions!(voice_agent, e.message)
  end

  def raw_instructions
    value = params[:instructions]
    return value.to_unsafe_h if value.is_a?(ActionController::Parameters)

    value
  end

  def reject_instruction_conflict!(voice_agent, prompt_provided, instructions_provided)
    if prompt_provided && instructions_provided
      invalid_instructions!(voice_agent, 'prompt and instructions cannot be provided together')
    end
    return unless prompt_provided && voice_agent&.structured_instructions_stored?

    invalid_instructions!(voice_agent, 'prompt cannot replace structured instructions')
  end

  def invalid_instructions!(voice_agent, message)
    record = voice_agent || Current.account.voice_agents.new
    record.errors.add(:instructions, message)
    raise ActiveRecord::RecordInvalid, record
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

  def knowledge_source_ids_provided?
    voice_agent_request_params.key?('knowledge_source_ids')
  end

  def sync_inbox_assignments!(voice_agent)
    kept_setting_ids = inbox_settings_params.map do |assignment|
      sync_inbox_assignment!(voice_agent, assignment)
    end

    voice_agent.voice_inbox_settings.where.not(id: kept_setting_ids).destroy_all
  end

  def sync_knowledge_sources!(voice_agent)
    AiKnowledgeSources::AssignmentSync.new(
      assistant: voice_agent,
      source_ids: voice_agent_request_params['knowledge_source_ids']
    ).perform
  end

  def inbox_settings_params
    Array.wrap(voice_agent_request_params['inbox_settings'])
  end

  def sync_inbox_assignment!(voice_agent, assignment)
    inbox = Current.account.inboxes.find(assignment['inbox_id'])
    setting = Current.account.voice_inbox_settings.find_or_initialize_by(inbox: inbox)
    setting.voice_agent = voice_agent
    setting.fallback_team_id = assignment['fallback_team_id'].presence
    setting.recording_enabled = ActiveModel::Type::Boolean.new.cast(assignment['recording_enabled']) if assignment.key?('recording_enabled')
    setting.settings = assignment['settings'] if assignment['settings'].is_a?(Hash)
    setting.save!
    setting.id
  end

  def render_readiness_error
    render json: { error: 'Complete the required setup before publishing.', readiness: @voice_agent.readiness }, status: :unprocessable_entity
  end
end
