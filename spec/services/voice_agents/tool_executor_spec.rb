require 'rails_helper'

RSpec.describe VoiceAgents::ToolExecutor do
  describe '.perform!' do
    let(:account) { create(:account) }
    let(:api_channel) { create(:channel_api, account: account) }
    let(:inbox) { api_channel.inbox }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:voice_agent) { create(:voice_agent, account: account) }
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

    it 'keeps human handoff enabled and rejects other disabled tools' do
      voice_agent.update!(
        tools_config: VoiceAgents::Config.new('enabled' => [VoiceAgents::Config::HUMAN_HANDOFF_TOOL]).normalized_config
      )

      result = described_class.perform!(
        call: call,
        voice_agent: voice_agent,
        tool_key: VoiceAgents::Config::END_CUSTOMER_CALL_TOOL,
        args: { reason: 'agent please' },
        external_id: 'tool-1'
      )

      expect(result[:status]).to eq('rejected')
      expect(result.dig(:result, :error_code)).to eq('tool_not_enabled')
      expect(call.voice_tool_events.find_by!(external_id: 'tool-1')).to have_attributes(
        tool: VoiceAgents::Config::END_CUSTOMER_CALL_TOOL,
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
      expect(conversation.reload.additional_attributes).to include(
        'voice_ai_handoff_status' => 'requested',
        'voice_ai_handoff_call_id' => call.id
      )
      expect(call.voice_tool_events.find_by!(external_id: 'tool-2')).to have_attributes(
        tool: VoiceAgents::Config::HUMAN_HANDOFF_TOOL,
        status: 'executed'
      )
    end

    it 'executes ikas order lookup and masks customer identifiers in voice tool events' do
      account.enable_features('ikas_integration')
      voice_agent.update!(
        tools_config: VoiceAgents::Config.new('enabled' => [VoiceAgents::Config::IKAS_LOOKUP_ORDER_TOOL]).normalized_config
      )
      connection_status = instance_double(Integrations::Ikas::ConnectionStatus, payload: { state: 'connected' })
      lookup_service = instance_double(Integrations::Ikas::OrderLookupService)
      allow(Integrations::Ikas::ConnectionStatus).to receive(:new).with(account: account).and_return(connection_status)
      allow(Integrations::Ikas::OrderLookupService).to receive(:new).and_return(lookup_service)
      allow(lookup_service).to receive(:call).and_return(status: 'ok', result_type: 'show_order_status')

      result = described_class.perform!(
        call: call,
        voice_agent: voice_agent,
        tool_key: VoiceAgents::Config::IKAS_LOOKUP_ORDER_TOOL,
        args: { order_identifier: '30564', email: 'buyer@example.com', phone: '+905419719978', limit: 3 },
        external_id: 'tool-3'
      )

      expect(result[:status]).to eq('executed')
      expect(Integrations::Ikas::OrderLookupService).to have_received(:new).with(
        account: account,
        conversation: conversation,
        identifiers: {
          'order_identifier' => '30564',
          'email' => 'buyer@example.com',
          'phone' => '+905419719978'
        },
        limit: 3
      )
      expect(call.voice_tool_events.find_by!(external_id: 'tool-3')).to have_attributes(
        tool: VoiceAgents::Config::IKAS_LOOKUP_ORDER_TOOL,
        status: 'executed',
        arguments: {
          'order_identifier' => '30564',
          'email' => 'b***@example.com',
          'phone' => '***9978',
          'limit' => 3
        }
      )
    end
  end
end
