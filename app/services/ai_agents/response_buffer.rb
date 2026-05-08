class AiAgents::ResponseBuffer
  CONFIG_KEY = 'AI_AGENT_RESPONSE_BUFFER_SECONDS'.freeze
  DEFAULT_BUFFER_SECONDS = 5
  METADATA_KEY = 'ai_response_buffer'.freeze

  class << self
    def schedule!(message)
      if buffer_seconds.zero?
        AgentBots::AiResponseJob.perform_later(message)
        return
      end

      buffer_token = SecureRandom.uuid
      write_scheduled_metadata!(message, buffer_token)
      AgentBots::AiResponseJob.set(wait: buffer_seconds.seconds).perform_later(message, buffer_token)
    end

    def ready?(message, buffer_token)
      matching_metadata?(current_metadata(message.conversation), message, buffer_token, 'scheduled')
    end

    def claim!(message, buffer_token)
      conversation = message.conversation.reload
      conversation.with_lock do
        metadata = current_metadata(conversation)
        next false unless matching_metadata?(metadata, message, buffer_token, 'scheduled')

        write_metadata!(conversation, metadata.merge('status' => 'claimed', 'claimed_at' => Time.current.iso8601(3)))
        true
      end
    end

    def complete!(message, buffer_token)
      conversation = message.conversation.reload
      conversation.with_lock do
        metadata = current_metadata(conversation)
        next false unless matching_metadata?(metadata, message, buffer_token, 'claimed')

        write_metadata!(conversation, metadata.merge('status' => 'completed', 'completed_at' => Time.current.iso8601(3)))
        true
      end
    end

    def buffer_seconds
      raw_value = GlobalConfig.get_value(CONFIG_KEY)
      value = Integer(raw_value.presence || DEFAULT_BUFFER_SECONDS)
      value.negative? ? 0 : value
    rescue ArgumentError, TypeError
      DEFAULT_BUFFER_SECONDS
    end

    private

    def write_scheduled_metadata!(message, buffer_token)
      conversation = message.conversation.reload
      conversation.with_lock do
        write_metadata!(conversation, scheduled_metadata(message, buffer_token))
      end
    end

    def scheduled_metadata(message, buffer_token)
      {
        'message_id' => message.id,
        'conversation_id' => message.conversation_id,
        'token' => buffer_token,
        'status' => 'scheduled',
        'expires_at' => buffer_seconds.seconds.from_now.iso8601(3),
        'updated_at' => Time.current.iso8601(3)
      }
    end

    def current_metadata(conversation)
      attrs = current_additional_attributes(conversation)
      metadata = attrs[METADATA_KEY]
      metadata.is_a?(Hash) ? metadata : {}
    end

    def current_additional_attributes(conversation)
      attrs = conversation.additional_attributes
      attrs.is_a?(Hash) ? attrs.deep_stringify_keys : {}
    end

    def write_metadata!(conversation, metadata)
      conversation.update!(additional_attributes: current_additional_attributes(conversation).merge(METADATA_KEY => metadata))
    end

    def matching_metadata?(metadata, message, buffer_token, status)
      metadata['message_id'].to_i == message.id &&
        metadata['conversation_id'].to_i == message.conversation_id &&
        metadata['token'] == buffer_token &&
        metadata['status'] == status
    end
  end
end
