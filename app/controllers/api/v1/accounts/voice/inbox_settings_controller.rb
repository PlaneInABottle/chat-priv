class Api::V1::Accounts::Voice::InboxSettingsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_admin_authorization?
  before_action :ensure_voice_ai_enabled, only: [:create, :update]
  before_action :set_setting, only: [:show, :update]

  def index
    settings = Current.account.voice_inbox_settings.includes(:inbox).order(:created_at)
    render json: { payload: settings.map { |setting| serialize(setting) } }
  end

  def show
    render json: serialize(@setting)
  end

  def create
    inbox = Current.account.inboxes.find(params.require(:inbox_id))
    setting = Current.account.voice_inbox_settings.create!(voice_setting_params.merge(inbox: inbox))
    render json: serialize(setting), status: :created
  end

  def update
    @setting.update!(voice_setting_params)
    render json: serialize(@setting)
  end

  private

  def set_setting
    @setting = Current.account.voice_inbox_settings.find(params[:id])
  end

  def voice_setting_params
    params.permit(:voice_agent_id, :fallback_team_id, :status, :livekit_room_prefix, :recording_enabled, settings: {})
  end

  def serialize(setting)
    payload = Voice::InboxSettingSerializer.new(setting).payload
    payload.merge(voice_agent: setting.voice_agent ? VoiceAgents::Serializer.new(setting.voice_agent).payload : nil)
  end
end
