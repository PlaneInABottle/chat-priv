# frozen_string_literal: true

class Integrations::Ikas::AdminApiClient
  DEFAULT_GRAPHQL_URL = 'https://api.myikas.com/api/v1/admin/graphql'
  TOKEN_PATH = '/api/admin/oauth/token'
  TOKEN_TIMEOUT = 15
  GRAPHQL_TIMEOUT = 30

  class Error < StandardError; end

  def initialize(store_host:, client_id:, client_secret:, graphql_url: ENV.fetch('IKAS_API_URL', DEFAULT_GRAPHQL_URL))
    @store_host = normalize_store_host(store_host)
    @client_id = client_id.to_s
    @client_secret = client_secret.to_s
    @graphql_url = graphql_url
  end

  def execute(query, variables = {})
    response = HTTParty.post(
      graphql_url,
      body: { query: query, variables: variables.presence || {} }.to_json,
      headers: graphql_request_headers,
      timeout: GRAPHQL_TIMEOUT
    )
    payload = parse_json(response.body)

    raise Error, "Ikas GraphQL HTTP #{response.code}" unless response.success?
    raise Error, "Ikas GraphQL errors: #{payload['errors'].to_json}" if payload['errors'].present?

    payload.fetch('data')
  end

  private

  attr_reader :store_host, :client_id, :client_secret, :graphql_url

  def access_token
    @access_token ||= begin
      raise Error, 'Ikas store host is invalid' if store_host.blank?

      response = HTTParty.post(
        token_url,
        body: token_request_body,
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        timeout: TOKEN_TIMEOUT
      )
      payload = parse_json(response.body)

      raise Error, "Ikas token HTTP #{response.code}" unless response.success?
      raise Error, 'Ikas token response missing access_token' if payload['access_token'].blank?

      payload.fetch('access_token')
    end
  end

  def graphql_request_headers
    {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{access_token}"
    }
  end

  def token_url
    "https://#{store_host}#{TOKEN_PATH}"
  end

  def token_request_body
    {
      grant_type: 'client_credentials',
      client_id: client_id,
      client_secret: client_secret
    }
  end

  def parse_json(body)
    JSON.parse(body)
  rescue JSON::ParserError => e
    raise Error, "Ikas response parse failed: #{e.message}"
  end

  def normalize_store_host(value)
    candidate = value.to_s.strip
    candidate = "https://#{candidate}" unless candidate.match?(%r{\Ahttps?://}i)

    uri = URI.parse(candidate)
    host = uri.host.to_s.downcase.delete_suffix('.')
    return if host.blank? || !host.match?(/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.myikas\.com\z/)

    host
  rescue URI::InvalidURIError
    nil
  end
end
