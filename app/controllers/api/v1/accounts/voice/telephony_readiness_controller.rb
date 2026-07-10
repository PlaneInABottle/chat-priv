class Api::V1::Accounts::Voice::TelephonyReadinessController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_admin_authorization?
  before_action :ensure_voice_ai_enabled

  def show
    numbers = Current.account.voice_numbers.includes(:voice_inbox_setting, :voice_provider_connection).order(:phone_number)
    render json: {
      configured: numbers.active.exists?,
      numbers: numbers.map { |number| serialize_number(number) }
    }
  end

  private

  def serialize_number(number)
    {
      id: number.id,
      phone_number: number.phone_number,
      status: number.status,
      inbox_id: number.voice_inbox_setting.inbox_id,
      voice_agent_id: number.voice_inbox_setting.voice_agent_id,
      provider: number.voice_provider_connection.provider,
      provider_status: number.voice_provider_connection.status
    }
  end
end
