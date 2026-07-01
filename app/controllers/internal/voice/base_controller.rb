class Internal::Voice::BaseController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
  rescue_from Voice::Usage::Admission::Error, with: :render_usage_rejected

  before_action :authenticate_internal_token!

  private

  def render_record_invalid(error)
    render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_content
  end

  def render_not_found(error)
    render json: { error: error.message }, status: :not_found
  end

  def render_usage_rejected(error)
    delete_livekit_room_for_rejected_context
    render json: { error: error.message, error_code: 'voice_usage_rejected' }, status: :too_many_requests
  end

  def delete_livekit_room_for_rejected_context
    room_name = params[:provider_call_id].to_s
    return if room_name.blank?

    Voice::Livekit::RoomService.delete_room_name(room_name: room_name)
  rescue StandardError => e
    Rails.logger.warn("livekit rejected room cleanup failed room=#{room_name} error=#{e.class.name}: #{e.message}")
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
