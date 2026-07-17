# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgents::EffectivePromptPreview do
  let(:account) { create(:account) }

  describe '#effective_system_prompt' do
    it 'combines the configured base prompt, agent prompt, and enabled tool policies', :aggregate_failures do
      upsert_config('AI_AGENT_GLOBAL_INSTRUCTIONS', 'Always answer in Turkish unless the customer uses English.')
      ai_agent = build(
        :ai_agent,
        account: account,
        prompt: 'Only answer from verified catalog evidence.',
        config: {
          'tools' => {
            'enabled' => %w[human_handoff ikas_catalog_search ikas_lookup_order]
          }
        }
      )

      preview = described_class.new(ai_agent: ai_agent)

      expect(preview.base_prompt).to eq('Always answer in Turkish unless the customer uses English.')
      expect(preview.global_instructions_prompt).to be_nil
      expect(preview.agent_prompt).to include('Only answer from verified catalog evidence.')
      expect(preview.tool_policy_prompt).to include('Catalog tool rules')
      expect(preview.tool_policy_prompt).to include('Order lookup tool rules')
      expect(preview.effective_system_prompt).to include(
        'Always answer in Turkish unless the customer uses English.',
        'Only answer from verified catalog evidence.',
        'The latest customer message controls product/category scope',
        'only gives dimensions or measurements and there is no clear previous product/category context',
        'do not add the previous product/category as an extra `queries` entry',
        'You may add your own reasoning, comparisons, and recommendations',
        'Do not list store categories, previous products, or examples unless the tool returned them',
        'Use stock evidence to avoid recommending unavailable products',
        'Avoid robotic field-label blocks',
        'Never write ₺, TL, TRY, $, €, or any currency symbol/code unless price.currency is present',
        'Never reveal or repeat customer email, phone, billing address, shipping address'
      )
      effective_prompt = preview.effective_system_prompt
      expect(effective_prompt.index('Always answer in Turkish')).to be < effective_prompt.index('AI agent instructions')
      expect(effective_prompt.index('AI agent instructions')).to be < effective_prompt.index('Catalog tool rules')
    end

    it 'omits a blank base prompt' do
      upsert_config('AI_AGENT_GLOBAL_INSTRUCTIONS', nil)
      ai_agent = build(:ai_agent, account: account, prompt: 'Answer briefly.')
      preview = described_class.new(ai_agent: ai_agent)

      expect(preview.base_prompt).to be_nil
      expect(preview.global_instructions_prompt).to be_nil
      expect(preview.effective_system_prompt).to include('AI agent instructions')
    end
  end

  describe '#enabled_tool_definitions' do
    it 'returns registry definitions and integration gate metadata for enabled tools' do
      ai_agent = build(
        :ai_agent,
        account: account,
        config: {
          'tools' => {
            'enabled' => %w[ikas_lookup_order ikas_catalog_search]
          }
        }
      )

      preview = described_class.new(ai_agent: ai_agent)

      expect(preview.enabled_tool_definitions.map(&:key)).to eq(
        %w[human_handoff ikas_lookup_order ikas_catalog_search present_options]
      )
      expect(preview.integration_gates.map { |gate| gate[:tool_key] }).to eq(
        %w[human_handoff ikas_lookup_order ikas_catalog_search present_options]
      )
      expect(preview.integration_gates.map { |gate| gate[:app_id] }).to eq([nil, 'ikas', 'ikas', nil])
    end
  end

  def upsert_config(name, value)
    InstallationConfig.where(name: name).first_or_initialize.tap do |config|
      config.value = value
      config.locked = false
      config.save!
    end
  end
end
