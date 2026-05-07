class Integrations::Ikas::ConnectionValidator
  IKAS_API_URL = 'https://api.myikas.com/api/v1/admin/graphql'.freeze
  TOKEN_PATH = '/api/admin/oauth/token'.freeze
  ME_QUERY = '{me { id }}'.freeze

  Result = Struct.new(
    :success?,
    :error_code,
    :error_message,
    :store_host,
    :client_id,
    :client_secret,
    :last_validated_at,
    keyword_init: true
  )

  def initialize(client_id:, client_secret:, store_url:, existing_secret: nil, existing_client_id: nil)
    @client_id = client_id
    @client_secret = client_secret
    @store_url = store_url
    @existing_secret = existing_secret
    @existing_client_id = existing_client_id
  end

  def perform
    return failure_result('missing_required_fields') if resolved_client_id.blank? || resolved_client_secret.blank? || store_url.blank?

    normalized_host = normalize_store_host
    return failure_result('invalid_store_url') if normalized_host.blank?

    token = fetch_access_token(normalized_host)
    return token if token.is_a?(Result)

    probe_result = validate_graphql_probe(token)
    return probe_result if probe_result.is_a?(Result)

    Result.new(
      success?: true,
      store_host: normalized_host,
      client_id: resolved_client_id,
      client_secret: resolved_client_secret,
      last_validated_at: Time.current.iso8601
    )
  end

  private

  attr_reader :client_id, :client_secret, :store_url, :existing_secret

  def resolved_client_id
    client_id.presence || @existing_client_id
  end

  def resolved_client_secret
    client_secret.presence || existing_secret
  end

  def normalize_store_host
    candidate = store_url.to_s.strip
    candidate = "https://#{candidate}" unless candidate.match?(%r{\Ahttps?://}i)

    uri = URI.parse(candidate)
    host = uri.host.to_s.downcase.delete_suffix('.')
    return if host.blank? || !host.match?(/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.myikas\.com\z/)

    host
  rescue URI::InvalidURIError
    nil
  end

  def fetch_access_token(store_host)
    response = HTTParty.post(
      token_url(store_host),
      body: token_request_body,
      headers: token_request_headers,
      timeout: 10
    )

    return failure_result(error_code_for_token_response(response)) unless response.success?

    payload = JSON.parse(response.body)
    access_token = payload['access_token']
    return failure_result('auth_failed') if access_token.blank?

    access_token
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    failure_result('timeout')
  rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET, OpenSSL::SSL::SSLError, HTTParty::Error
    failure_result('network_error')
  rescue JSON::ParserError
    failure_result('auth_failed')
  end

  def validate_graphql_probe(access_token)
    response = HTTParty.post(
      IKAS_API_URL,
      body: { query: ME_QUERY }.to_json,
      headers: graphql_request_headers(access_token),
      timeout: 10
    )

    return failure_result(error_code_for_probe_response(response)) unless response.success?

    payload = JSON.parse(response.body)
    return failure_result('probe_failed') if payload['errors'].present? || payload.dig('data', 'me', 'id').blank?

    true
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    failure_result('timeout')
  rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET, OpenSSL::SSL::SSLError, HTTParty::Error
    failure_result('network_error')
  rescue JSON::ParserError
    failure_result('probe_failed')
  end

  def token_url(store_host)
    "https://#{store_host}#{TOKEN_PATH}"
  end

  def token_request_body
    {
      grant_type: 'client_credentials',
      client_id: resolved_client_id,
      client_secret: resolved_client_secret
    }
  end

  def token_request_headers
    { 'Content-Type' => 'application/x-www-form-urlencoded' }
  end

  def graphql_request_headers(access_token)
    {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{access_token}"
    }
  end

  def error_code_for_token_response(response)
    return 'rate_limited' if response.code == 429
    return 'auth_failed' if [401, 403].include?(response.code)

    'auth_failed'
  end

  def error_code_for_probe_response(response)
    return 'rate_limited' if response.code == 429
    return 'auth_failed' if [401, 403].include?(response.code)

    'probe_failed'
  end

  def failure_result(error_code)
    Result.new(
      success?: false,
      error_code: error_code,
      error_message: I18n.t("errors.ikas.#{error_code}", default: error_code.humanize)
    )
  end
end
