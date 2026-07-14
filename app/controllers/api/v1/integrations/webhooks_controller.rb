class Api::V1::Integrations::WebhooksController < ApplicationController
  SLACK_SIGNATURE_VERSION = 'v0'.freeze
  SLACK_SIGNATURE_TOLERANCE = 5.minutes.to_i

  before_action :verify_slack_signature!

  def create
    builder = Integrations::Slack::IncomingMessageBuilder.new(permitted_params)
    response = builder.perform
    render json: response
  end

  private

  def permitted_params
    params.permit(
      :api_app_id,
      :challenge,
      :event_id,
      :event_time,
      :team_id,
      :type,
      event: [
        :channel,
        :subtype,
        :text,
        :thread_ts,
        :ts,
        :type,
        :user,
        { blocks: [:type], files: [:filetype, :mimetype, :url_private], links: [:domain, :url] }
      ]
    )
  end

  def verify_slack_signature!
    signing_secret = GlobalConfigService.load('SLACK_SIGNING_SECRET', nil)
    timestamp = Integer(request.headers['X-Slack-Request-Timestamp'], exception: false)
    signature = request.headers['X-Slack-Signature']

    return head :unauthorized if signing_secret.blank? || timestamp.blank? || signature.blank?
    return head :unauthorized if (Time.current.to_i - timestamp).abs > SLACK_SIGNATURE_TOLERANCE

    signature_base = "#{SLACK_SIGNATURE_VERSION}:#{timestamp}:#{request.raw_post}"
    expected_signature = "#{SLACK_SIGNATURE_VERSION}=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, signature_base)}"
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected_signature, signature)
  end
end
