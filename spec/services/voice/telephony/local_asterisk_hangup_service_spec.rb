require 'rails_helper'

RSpec.describe Voice::Telephony::LocalAsteriskHangupService do
  let(:account) { create(:account) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:voice_agent) { account.voice_agents.first! }
  let(:voice_inbox_setting) { create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent) }
  let(:provider_connection) do
    create(
      :voice_provider_connection,
      account: account,
      provider: 'test_sip',
      settings: { 'kind' => 'local_asterisk' }
    )
  end
  let(:voice_number) do
    create(
      :voice_number,
      account: account,
      voice_provider_connection: provider_connection,
      voice_inbox_setting: voice_inbox_setting,
      settings: { 'softphone_user' => '1001' }
    )
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider: :livekit,
      provider_call_id: 'local-sip-room-1',
      meta: {
        'voice_provider_connection_id' => provider_connection.id,
        'voice_number_id' => voice_number.id
      }
    )
  end
  let(:success_status) { instance_double(Process::Status, success?: true) }

  before do
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(described_class::COMPOSE_FILE).and_return(true)
  end

  it 'skips outside development' do
    expect(described_class.perform(call: call)).to eq(
      'status' => 'skipped',
      'reason' => 'not_local_asterisk_harness'
    )
  end

  it 'requests hangup for matching local Asterisk PJSIP channels in development' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
    allow(Open3).to receive(:capture3).and_return(
      [
        [
          'PJSIP/1001-00000001!from-softphone!9000!2!Up!Dial!PJSIP/+908501112233@livekit,60',
          'PJSIP/livekit-00000002!from-livekit!s!1!Up!AppDial!(Outgoing Line)',
          'Local/ignored-00000003!default!s!1!Up!Echo!'
        ].join("\n"),
        '',
        success_status
      ],
      ['Requested hangup', '', success_status]
    )

    result = described_class.perform(call: call)

    expect(result).to include(
      'status' => 'requested',
      'channels' => ['PJSIP/1001-00000001', 'PJSIP/livekit-00000002']
    )
    expect(Open3).to have_received(:capture3).with(
      'docker',
      'compose',
      '-f',
      described_class::COMPOSE_FILE,
      'exec',
      '-T',
      described_class::ASTERISK_SERVICE,
      'asterisk',
      '-rx',
      'channel request hangup PJSIP/1001-00000001 PJSIP/livekit-00000002'
    )
  end

  it 'does not request hangup when no matching channels are active' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
    allow(Open3).to receive(:capture3).and_return(
      ["PJSIP/other-00000001!default!s!1!Up!Echo!\n", '', success_status]
    )

    result = described_class.perform(call: call)

    expect(result).to eq('status' => 'not_found', 'channels' => [])
    expect(Open3).to have_received(:capture3).once
  end
end
