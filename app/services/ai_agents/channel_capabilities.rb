# frozen_string_literal: true

class AiAgents::ChannelCapabilities
  def self.present_options?(mode:, conversation:)
    return true if mode.to_s == 'test'
    return false unless mode.to_s == 'live'

    conversation&.inbox&.channel&.supports_ai_input_select? == true
  end

  def self.catalog_product_images?(mode:, conversation:)
    return true if mode.to_s == 'test'

    conversation&.inbox&.channel&.supports_ai_catalog_product_images? == true
  end
end
