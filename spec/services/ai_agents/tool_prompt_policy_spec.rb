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

  it 'preserves customer constraints and prefers native choices over repeated or handwritten questions' do
    instructions = described_class.new(
      [AiAgents::Config::PRESENT_OPTIONS_TOOL, AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL]
    ).instructions

    expect(instructions).to match(/latest customer message.*previously stated constraints/i)
    expect(instructions).to match(/do not re-ask.*answered.*declined/i)
    expect(instructions).to match(/asks you to recommend.*grounded reason/i)
    expect(instructions).to match(/do not write.*markdown bullets/i)
  end

  it 'applies recommendation discipline without native option presentation' do
    instructions = described_class.new([AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL]).instructions

    expect(instructions).to include('Shared conversation rules:')
    expect(instructions).to match(/latest customer message.*previously stated constraints.*unchanged/i)
    expect(instructions).to match(/asks.*recommend.*grounded reason/i)
    expect(instructions).to match(/at most one necessary follow-up/i)
    expect(instructions).to match(/comparative price or durability claims.*exact tool evidence/i)
    expect(instructions).to match(/interactive choices are unavailable.*concise plain text/i)
    expect(instructions).not_to include('Customer option rules:', '`present_options`')
  end

  it 'requires explicit candidate evidence for physical product claims' do
    instructions = described_class.new([AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL]).instructions

    expect(instructions).to match(/material.*durability.*pet-resistance.*damage.*suitability.*candidate evidence/i)
    expect(instructions).to match(/names.*neutral catalog facts.*not evidence.*physical performance.*pet behavior/i)
  end

  it 'keeps shared conversation rules when the merchant disables native options' do
    instructions = described_class.new([]).instructions

    expect(instructions).to include('Shared conversation rules:')
    expect(instructions).not_to include('Customer option rules:', '`present_options`')
  end
end
