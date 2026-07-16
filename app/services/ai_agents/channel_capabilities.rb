# frozen_string_literal: true

class AiAgents::ChannelCapabilities
  PRESENT_OPTIONS_CHANNEL_TYPES = %w[Channel::WebWidget Channel::Whatsapp].freeze

  def self.present_options?(mode:, conversation:)
    return true if mode.to_s == 'test'
    return false unless mode.to_s == 'live'

    PRESENT_OPTIONS_CHANNEL_TYPES.include?(conversation&.inbox&.channel_type)
  end
end
