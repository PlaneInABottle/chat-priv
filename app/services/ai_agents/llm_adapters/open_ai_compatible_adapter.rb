# frozen_string_literal: true

class AiAgents::LlmAdapters::OpenAiCompatibleAdapter < AiAgents::LlmAdapters::BaseAdapter
  class RequestFailed < StandardError; end

  DEFAULT_COMPLETION_TOKEN_LIMIT = 2_048
  MAX_COMPLETION_TOKEN_LIMIT = 4_096

  def perform(messages:, tools:, tool_choice: 'auto', max_tokens: nil)
    usage_event = reserve_improvement_credit
    response = make_api_request(
      messages: messages,
      tools: tools,
      tool_choice: tool_choice,
      max_tokens: completion_token_limit(max_tokens)
    )
    normalized = normalize_response(response)
    consume_improvement_credit(usage_event, normalized[:usage])
    normalized
  rescue StandardError
    improvement_limiter&.release!(usage_event)
    raise
  end

  private

  def make_api_request(messages:, tools:, tool_choice:, max_tokens:)
    uri = URI(api_endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = api_timeout

    request = Net::HTTP::Post.new(uri.path, headers)
    request.body = request_body(messages: messages, tools: tools, tool_choice: tool_choice, max_tokens: max_tokens).to_json

    response = http.request(request)
    raise RequestFailed, "LLM request failed with HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

    JSON.parse(response.body)
  end

  def request_body(messages:, tools:, tool_choice:, max_tokens:)
    body = {
      model: account.ai_agent_model,
      messages: build_messages(messages),
      temperature: temperature.nil? ? 0.2 : temperature,
      max_tokens: max_tokens
    }
    body[:tools] = tools if tools.present?
    body[:tool_choice] = tool_choice if tools.present?
    body[:response_format] = response_format if response_format.present?
    body
  end

  def completion_token_limit(override)
    requested = (override || max_tokens || DEFAULT_COMPLETION_TOKEN_LIMIT).to_i
    requested.clamp(1, MAX_COMPLETION_TOKEN_LIMIT)
  end

  def build_messages(messages)
    history = messages.map do |msg|
      next tool_result_message(msg) if msg[:role].to_s == 'tool'

      {
        role: msg[:role] || 'user',
        content: msg.key?(:content) ? msg[:content] : msg.to_s,
        tool_calls: msg[:tool_calls]
      }.compact
    end

    [{ role: 'system', content: system_prompt }, *history]
  end

  def tool_result_message(msg)
    {
      role: 'tool',
      tool_call_id: msg[:tool_call_id],
      content: msg[:content] || ''
    }
  end

  def normalize_response(response)
    choice = response.dig('choices', 0) || {}
    message = choice['message'] || {}

    {
      assistant_text: message['content'],
      tool_calls: normalize_tool_calls(message['tool_calls']),
      finish_reason: choice['finish_reason'],
      usage: response['usage'],
      raw_response: response
    }
  end

  def reserve_improvement_credit
    return unless improvement_limiter

    improvement_limiter.reserve_or_raise!(metadata: { 'model' => account.ai_agent_model })
  end

  def consume_improvement_credit(event, usage)
    return unless event

    improvement_limiter.consume!(
      event,
      unit_type: 'tokens',
      units: total_tokens(usage),
      metadata: { 'model' => account.ai_agent_model }
    )
  end

  def total_tokens(usage)
    payload = usage.to_h.with_indifferent_access
    return payload[:total_tokens].to_i if payload.key?(:total_tokens)

    payload[:prompt_tokens].to_i + payload[:completion_tokens].to_i
  end

  def improvement_limiter
    return if improvement_operation.blank?

    @improvement_limiter ||= AiImprovements::Usage::Limiter.new(
      account: account,
      operation: improvement_operation,
      ai_agent: ai_agent,
      initiated_by: initiated_by
    )
  end

  def normalize_tool_calls(tool_calls)
    Array(tool_calls).map do |tool_call|
      {
        id: tool_call['id'],
        type: tool_call['type'],
        name: tool_call.dig('function', 'name'),
        arguments: tool_call.dig('function', 'arguments')
      }
    end
  end

  def headers
    {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{api_key}",
      'HTTP-Referer' => 'https://www.kozmopath.com',
      'X-Title' => 'Kozmopath AI Agent'
    }
  end

  def api_endpoint
    AiAgents::Settings.llm_endpoint
  end

  def api_key
    AiAgents::Settings.llm_api_key
  end

  def api_timeout
    AiAgents::Settings.llm_timeout_seconds
  end
end
