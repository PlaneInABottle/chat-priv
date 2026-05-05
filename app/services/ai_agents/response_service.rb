# frozen_string_literal: true

module AiAgents
  class ResponseService
    SYSTEM_PROMPT_TEMPLATE = <<~PROMPT
      You are a helpful AI assistant for a customer support team.
      Follow these instructions carefully:

      %{prompt}

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

      response = make_api_request
      response.dig('choices', 0, 'message', 'content')
    rescue StandardError => e
      Rails.logger.error "[AiAgents::ResponseService] Error: #{e.message}"
      nil
    end

    private

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
        'HTTP-Referer' => 'https://chatwoot.com',
        'X-Title' => 'Chatwoot AI Agent'
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
        content: SYSTEM_PROMPT_TEMPLATE % { prompt: @ai_agent.prompt }
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
      ENV.fetch('AI_AGENTS_SIMULATOR_ENDPOINT', 'https://openrouter.ai/api/v1/chat/completions')
    end

    def api_key
      ENV.fetch('AI_AGENTS_SIMULATOR_API_KEY', '')
    end

    def api_timeout
      ENV.fetch('AI_AGENTS_SIMULATOR_TIMEOUT_SECONDS', '20').to_i
    end
  end
end
