require 'rails_helper'
require Rails.root.join('db/migrate/20260611143000_backfill_voice_ai_enabled_for_existing_voice_agents')

RSpec.describe BackfillVoiceAiEnabledForExistingVoiceAgents do
  subject(:migration) { described_class.new }

  it 'enables previously configured voice accounts and backfills default agents without enabling access' do
    enabled_account = create(:account, settings: {})
    disabled_agent_account = create(:account, settings: {})
    configured_account = create(:account, settings: { voice_ai_enabled: false })
    old_account_without_agents = create(:account, settings: {})
    create(:voice_agent, account: enabled_account, enabled: true)
    create(:voice_agent, account: disabled_agent_account, enabled: false)

    migration.up
    migration.up

    expect(enabled_account.reload.settings['voice_ai_enabled']).to be(true)
    expect(disabled_agent_account.reload.settings).not_to have_key('voice_ai_enabled')
    expect(configured_account.reload.settings['voice_ai_enabled']).to be(false)
    expect(old_account_without_agents.reload.settings).not_to have_key('voice_ai_enabled')
    expect(old_account_without_agents.voice_agents.count).to eq(1)
    expect(old_account_without_agents.voice_agents.first).to have_attributes(
      name: 'Voice Assistant',
      enabled: true,
      language: 'tr',
      voice: 'Charon'
    )
    expect(old_account_without_agents.voice_agents.first.config['backfilled_default_agent']).to be(true)

    migration.down

    expect(enabled_account.reload.settings['voice_ai_enabled']).to be(true)
  end
end
