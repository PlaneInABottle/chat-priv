require 'rails_helper'

RSpec.describe AiAgents::ToolPromptPolicy do
  it 'always explains when and how to use built-in customer options' do
    instructions = described_class.new([AiAgents::Config::PRESENT_OPTIONS_TOOL]).instructions

    expect(instructions).to include('When `present_options` is available')
    expect(instructions).to include('Do not use `present_options` for open-ended values')
    expect(instructions).to include('must use `catalog_option_ids`')
    expect(instructions).to include('Call `ikas_catalog_search` first')
    expect(instructions).to include('Do not mention options tooling')
  end

  it 'omits option instructions when the merchant disables the capability' do
    expect(described_class.new([]).instructions).to be_nil
  end
end
