class Internal::Voice::BaseController < ActionController::API
  rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid

  before_action :authenticate_internal_token!

  private

  def render_record_invalid(error)
    render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_content
  end

  def authenticate_internal_token!
    expected = ENV['VOICE_AGENT_INTERNAL_TOKEN'].presence
    return render json: { error: 'VOICE_AGENT_INTERNAL_TOKEN is not configured' }, status: :service_unavailable unless expected

    provided = request.headers['X-Voice-Agent-Token'].to_s
    return if secure_token_match?(provided, expected)

    render json: { error: 'Unauthorized' }, status: :unauthorized
  end

  def secure_token_match?(provided, expected)
    return false if provided.blank?
    return false unless provided.bytesize == expected.bytesize

    ActiveSupport::SecurityUtils.secure_compare(provided, expected)
  end
end
