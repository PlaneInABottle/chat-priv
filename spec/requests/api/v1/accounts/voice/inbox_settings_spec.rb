require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Voice::InboxSettings', type: :request do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:channel_api, account: account).inbox }

  it 'accepts and returns a technology-neutral room prefix' do
    post "/api/v1/accounts/#{account.id}/voice/inbox_settings",
         params: { inbox_id: inbox.id, room_prefix: 'kozmopath' },
         headers: admin.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('room_prefix' => 'kozmopath')
    expect(response.parsed_body).not_to have_key('livekit_room_prefix')
    expect(VoiceInboxSetting.last.livekit_room_prefix).to eq('kozmopath')
  end
end
