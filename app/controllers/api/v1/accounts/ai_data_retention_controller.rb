class Api::V1::Accounts::AiDataRetentionController < Api::V1::Accounts::BaseController
  SETTING_ATTRIBUTES = {
    'text' => :ai_agent_data_retention_days,
    'voice' => :voice_ai_data_retention_days
  }.freeze

  before_action :current_account
  before_action :check_admin_authorization?

  def show
    render json: retention_payload
  end

  def update
    return render_invalid_kind unless AiDataRetention::Policy.valid_kind?(retention_params[:kind])
    return render_invalid_days unless AiDataRetention::Policy.valid_days?(retention_params[:days])

    Current.account.update!(SETTING_ATTRIBUTES.fetch(retention_params[:kind]) => retention_params[:days].to_i)
    render json: retention_payload
  end

  def purge
    return render_invalid_kind unless AiDataRetention::Policy.valid_kind?(retention_params[:kind])

    AiDataRetention::PurgeAccountJob.perform_later(Current.account.id, retention_params[:kind])
    render json: { status: 'queued', kind: retention_params[:kind] }, status: :accepted
  end

  private

  def retention_params
    params.permit(:kind, :days)
  end

  def retention_payload
    {
      text: { days: Current.account.ai_agent_data_retention_days },
      voice: { days: Current.account.voice_ai_data_retention_days },
      allowed_days: AiDataRetention::Policy::ALLOWED_DAYS
    }
  end

  def render_invalid_kind
    render json: { error: 'Retention kind must be text or voice.' }, status: :unprocessable_entity
  end

  def render_invalid_days
    render json: { error: 'Choose a supported retention duration.' }, status: :unprocessable_entity
  end
end
