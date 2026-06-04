# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgents::EffectivePromptPreview do
  describe '#effective_system_prompt' do
    it 'combines the base AI agent prompt with enabled tool policies' do
      ai_agent = create(
        :ai_agent,
        prompt: 'Only answer from verified catalog evidence.',
        config: {
          'tools' => {
            'enabled' => %w[human_handoff ikas_catalog_search]
          }
        }
      )

      preview = described_class.new(ai_agent: ai_agent)

      expect(preview.base_prompt).to include('Only answer from verified catalog evidence.')
      expect(preview.tool_policy_prompt).to include('Catalog tool rules')
      expect(preview.effective_system_prompt).to include(
        'Only answer from verified catalog evidence.',
        'Do not mention a price currency when price.currency is blank'
      )
    end
  end

  describe '#enabled_tool_definitions' do
    it 'returns registry definitions and integration gate metadata for enabled tools' do
      ai_agent = create(
        :ai_agent,
        config: {
          'tools' => {
            'enabled' => %w[ikas_lookup_order ikas_catalog_search]
          }
        }
      )

      preview = described_class.new(ai_agent: ai_agent)

      expect(preview.enabled_tool_definitions.map(&:key)).to eq(%w[ikas_lookup_order ikas_catalog_search])
      expect(preview.integration_gates.map { |gate| gate[:tool_key] }).to eq(%w[ikas_lookup_order ikas_catalog_search])
      expect(preview.integration_gates.map { |gate| gate[:app_id] }).to all(eq('ikas'))
    end
  end
end
