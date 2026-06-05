# frozen_string_literal: true

class AiAgents::ResponseService
  SYSTEM_PROMPT_TEMPLATE = <<~PROMPT
    You are a helpful AI assistant for a customer support team.
    Follow these instructions carefully:

    %<prompt>s

    Be concise, professional, and helpful. If you cannot answer something,
    politely say so and suggest handing off to a human agent.
  PROMPT

  def initialize(ai_agent:, messages: [], conversation: nil)
    @ai_agent = ai_agent
    @messages = messages
    @conversation = conversation
    @account = ai_agent.account
  end

  def perform
    return nil unless @ai_agent.enabled?
    return nil unless @account.ai_agent_enabled?

    adapter.perform(messages: normalized_messages, tools: [], tool_choice: 'auto')[:assistant_text]
  rescue StandardError => e
    Rails.logger.error "[AiAgents::ResponseService] Error: #{e.message}"
    nil
  end

  private

  def adapter
    @adapter ||= AiAgents::LlmAdapters::OpenAiCompatibleAdapter.new(ai_agent: @ai_agent, account: @account)
  end

  def normalized_messages
    @messages.map { |msg| { role: msg[:role] || msg['role'], content: msg[:content] || msg['content'] } }
  end

  def make_api_request
    uri = URI(api_endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = api_timeout

    request = Net::HTTP::Post.new(uri.path, headers)
    request.body = request_body.to_json

    response = http.request(request)
    JSON.parse(response.body)
  end

  def headers
    {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{api_key}",
      'HTTP-Referer' => 'https://www.kozmopath.com',
      'X-Title' => 'Kozmopath AI Agent'
    }
  end

  def request_body
    {
      model: model,
      messages: build_messages,
      temperature: 0.7,
      max_tokens: 1024
    }
  end

  def build_messages
    system_msg = {
      role: 'system',
      content: AiAgents::PromptComposer.new(ai_agent: @ai_agent).effective_system_prompt
    }

    history = @messages.map do |msg|
      {
        role: msg[:role] || 'user',
        content: msg[:content] || msg.to_s
      }
    end

    [system_msg, *history]
  end

  def model
    @account.ai_agent_model
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
