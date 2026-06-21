require 'rails_helper'

RSpec.describe 'Super Admin voice numbers', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:voice_agent) { account.voice_agents.first! }
  let(:voice_inbox_setting) { create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent) }
  let(:provider_connection) { create(:voice_provider_connection, account: account, provider: 'test_sip') }

  it 'redirects unauthenticated users' do
    get '/super_admin/voice_numbers'

    expect(response).to have_http_status(:redirect)
  end

  it 'lists voice numbers for super admins' do
    number = create(
      :voice_number,
      account: account,
      voice_provider_connection: provider_connection,
      voice_inbox_setting: voice_inbox_setting
    )
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/voice_numbers'

    expect(response).to have_http_status(:success)
    expect(response.body).to include(number.phone_number)
  end

  it 'adds the settings card link' do
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/settings'

    expect(response.body).to include('Voice Telephony', '/super_admin/voice_numbers')
  end

  it 'creates a voice number without accepting raw JSON settings' do
    sign_in(super_admin, scope: :super_admin)
    phone_number = generate(:voice_phone_number)

    expect do
      post '/super_admin/voice_numbers',
           params: {
             voice_number: {
               account_id: account.id,
               voice_provider_connection_id: provider_connection.id,
               voice_inbox_setting_id: voice_inbox_setting.id,
               phone_number: phone_number.sub('+90', '+90 '),
               status: 'active',
               livekit_inbound_trunk_id: 'trunk-123',
               livekit_dispatch_rule_id: 'rule-123',
               settings: '{"routing_note":"local softphone"}'
             }
           }
    end.to change(VoiceNumber, :count).by(1)

    number = VoiceNumber.last
    expect(number).to have_attributes(
      account: account,
      voice_provider_connection: provider_connection,
      voice_inbox_setting: voice_inbox_setting,
      phone_number: phone_number,
      status: 'active',
      livekit_inbound_trunk_id: 'trunk-123',
      livekit_dispatch_rule_id: 'rule-123'
    )
    expect(number.settings).to eq({})
  end

  it 'ignores invalid settings JSON submitted outside the form' do
    sign_in(super_admin, scope: :super_admin)
    phone_number = generate(:voice_phone_number)

    post '/super_admin/voice_numbers',
         params: {
           voice_number: {
             account_id: account.id,
             voice_provider_connection_id: provider_connection.id,
             voice_inbox_setting_id: voice_inbox_setting.id,
             phone_number: phone_number,
             status: 'draft',
             settings: '{invalid-json'
           }
         }

    expect(response).to have_http_status(:redirect)
    expect(VoiceNumber.last.settings).to eq({})
  end

  it 'redacts secret-like settings on the show page' do
    number = create(
      :voice_number,
      account: account,
      voice_provider_connection: provider_connection,
      voice_inbox_setting: voice_inbox_setting,
      settings: {
        'routing_note' => 'local softphone',
        'auth_token' => 'secret-token',
        'access_key' => 'secret-access'
      }
    )
    sign_in(super_admin, scope: :super_admin)

    get "/super_admin/voice_numbers/#{number.id}"

    expect(response).to have_http_status(:success)
    expect(response.body).to include('local softphone', '[redacted]')
    expect(response.body).not_to include('secret-token', 'secret-access')
  end
end
