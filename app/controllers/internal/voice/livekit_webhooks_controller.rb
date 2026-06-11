class Internal::Voice::LivekitWebhooksController < ActionController::API
  def create
    payload = Voice::Livekit::WebhookVerifier.verify!(
      raw_body: request.raw_post,
      authorization_header: request.headers['Authorization']
    )
    render json: Voice::Recordings::WebhookHandler.perform!(payload: payload)
  rescue JWT::DecodeError, KeyError => e
    render json: { error: e.message }, status: :unauthorized
  rescue JSON::ParserError
    render json: { error: 'Invalid webhook payload' }, status: :bad_request
  end
end
