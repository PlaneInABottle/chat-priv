require 'rails_helper'

RSpec.describe AiAgents::ChannelCapabilities do
  it 'allows option presentation in test mode without a live inbox' do
    expect(described_class.present_options?(mode: :test, conversation: nil)).to be(true)
  end

  it 'allows option presentation for live widget and WhatsApp conversations only' do
    widget = Struct.new(:inbox).new(Struct.new(:channel_type).new('Channel::WebWidget'))
    whatsapp = Struct.new(:inbox).new(Struct.new(:channel_type).new('Channel::Whatsapp'))
    api = Struct.new(:inbox).new(Struct.new(:channel_type).new('Channel::Api'))

    expect(described_class.present_options?(mode: :live, conversation: widget)).to be(true)
    expect(described_class.present_options?(mode: :live, conversation: whatsapp)).to be(true)
    expect(described_class.present_options?(mode: :live, conversation: api)).to be(false)
  end
end
