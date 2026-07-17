require 'rails_helper'

RSpec.describe AiAgents::ChannelCapabilities do
  it 'allows option presentation in test mode without a live inbox' do
    expect(described_class.present_options?(mode: :test, conversation: nil)).to be(true)
  end

  it 'uses the channel-declared capability for live conversations' do
    supported_channel = instance_double(Channel::WebWidget, supports_ai_input_select?: true)
    unsupported_channel = instance_double(Channel::Api, supports_ai_input_select?: false)
    supported = Struct.new(:inbox).new(Struct.new(:channel).new(supported_channel))
    unsupported = Struct.new(:inbox).new(Struct.new(:channel).new(unsupported_channel))

    expect(described_class.present_options?(mode: :live, conversation: supported)).to be(true)
    expect(described_class.present_options?(mode: :live, conversation: unsupported)).to be(false)
  end
end
