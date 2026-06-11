require 'rails_helper'

RSpec.describe VoiceAgents::ToolExecutor do
  describe '.perform!' do
    let(:account) { create(:account) }
    let(:api_channel) { create(:channel_api, account: account) }
    let(:inbox) { api_channel.inbox }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:voice_agent) { account.voice_agents.first }
    let(:call) do
      create(
        :call,
        account: account,
        inbox: inbox,
        conversation: conversation,
        contact: conversation.contact,
        provider: :livekit,
        provider_call_id: 'room-1'
      )
    end

    it 'rejects disabled tools and records the rejection' do
      voice_agent.update!(
        tools_config: VoiceAgents::Config.new('enabled' => [VoiceAgents::Config::END_CUSTOMER_CALL_TOOL]).normalized_config
      )

      result = described_class.perform!(
        call: call,
        voice_agent: voice_agent,
        tool_key: VoiceAgents::Config::HUMAN_HANDOFF_TOOL,
        args: { reason: 'agent please' },
        external_id: 'tool-1'
      )

      expect(result[:status]).to eq('rejected')
      expect(result.dig(:result, :error_code)).to eq('tool_not_enabled')
      expect(call.voice_tool_events.find_by!(external_id: 'tool-1')).to have_attributes(
        tool: VoiceAgents::Config::HUMAN_HANDOFF_TOOL,
        status: 'rejected'
      )
    end

    it 'uses the call account and inbox when resolving fallback team settings' do
      local_team = create(:team, account: account)
      create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent, fallback_team: local_team)
      foreign_account = create(:account)
      foreign_setting = create(:voice_inbox_setting, account: foreign_account, fallback_team: create(:team, account: foreign_account))
      call.update!(meta: { 'voice_inbox_setting_id' => foreign_setting.id })

      result = described_class.perform!(
        call: call,
        voice_agent: voice_agent,
        tool_key: VoiceAgents::Config::HUMAN_HANDOFF_TOOL,
        args: { reason: 'agent please' },
        external_id: 'tool-2'
      )

      expect(result[:status]).to eq('executed')
      expect(conversation.reload.team).to eq(local_team)
      expect(call.reload.handoff_status).to eq('requested')
      expect(call.voice_tool_events.find_by!(external_id: 'tool-2')).to have_attributes(
        tool: VoiceAgents::Config::HUMAN_HANDOFF_TOOL,
        status: 'executed'
      )
    end
  end
end
