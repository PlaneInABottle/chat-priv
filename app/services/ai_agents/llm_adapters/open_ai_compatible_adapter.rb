# frozen_string_literal: true

module AiAgents
  module LlmAdapters
    class OpenAiCompatibleAdapter < BaseAdapter
      def perform(messages:, tools:, tool_choice: 'auto')
        response = make_api_request(messages: messages, tools: tools, tool_choice: tool_choice)
        normalize_response(response)
      end

      private

      def make_api_request(messages:, tools:, tool_choice:)
        uri = URI(api_endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = api_timeout

        request = Net::HTTP::Post.new(uri.path, headers)
        request.body = request_body(messages: messages, tools: tools, tool_choice: tool_choice).to_json

        response = http.request(request)
        JSON.parse(response.body)
      end

      def request_body(messages:, tools:, tool_choice:)
        {
          model: account.ai_agent_model,
          messages: build_messages(messages),
          temperature: 0.7,
          max_tokens: 1024,
          tools: tools,
          tool_choice: tool_choice
        }.compact
      end

      def build_messages(messages)
        history = messages.map do |msg|
          next tool_result_message(msg) if msg[:role].to_s == 'tool'

          {
            role: msg[:role] || 'user',
            content: msg[:content] || msg.to_s,
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
          'HTTP-Referer' => 'https://chatwoot.com',
          'X-Title' => 'Chatwoot AI Agent'
        }
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
end
