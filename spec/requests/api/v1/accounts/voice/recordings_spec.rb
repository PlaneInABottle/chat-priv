require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Voice::Recordings', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:call) do
    create(
      :call,
      conversation: conversation,
      account: account,
      inbox: inbox,
      contact: conversation.contact,
      provider: :livekit,
      status: 'completed'
    )
  end

  before do
    create(:inbox_member, inbox: inbox, user: agent)
  end

  it 'lists completed account recordings with signed replay URLs' do
    create(
      :voice_recording,
      call: call,
      status: 'completed',
      completed_at: Time.zone.now,
      duration_seconds: 30,
      bucket: 'voice-recordings-test',
      object_key: 'voice-recordings/account-1/call-1/room-1.mp4'
    )
    other_recording = create(:voice_recording, status: 'completed')
    unassigned_recording = create_same_account_unassigned_recording

    with_modified_env(recording_env) do
      get "/api/v1/accounts/#{account.id}/voice/recordings",
          params: { status: 'completed', limit: 10 },
          headers: agent.create_new_auth_token,
          as: :json
    end

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.size).to eq(1)
    expect(response.parsed_body.first).to include(
      'status' => 'completed',
      'duration_seconds' => 30,
      'call' => include(
        'id' => call.id,
        'inbox_id' => inbox.id
      )
    )
    expect(response.parsed_body.first['url']).to include('voice-recordings-test')
    expect(response.parsed_body.first['id']).not_to eq(other_recording.id)
    expect(response.parsed_body.first['id']).not_to eq(unassigned_recording.id)
  end

  it 'returns no results when filtering to an inbox the agent cannot access' do
    unassigned_recording = create_same_account_unassigned_recording

    get "/api/v1/accounts/#{account.id}/voice/recordings",
        params: { inbox_id: unassigned_recording.call.inbox_id },
        headers: agent.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to be_empty
  end

  def recording_env
    {
      'VOICE_RECORDING_S3_ACCESS_KEY_ID' => 'access-key',
      'VOICE_RECORDING_S3_SECRET_ACCESS_KEY' => 'secret-key',
      'VOICE_RECORDING_S3_BUCKET' => 'voice-recordings-test',
      'VOICE_RECORDING_S3_ENDPOINT' => 'https://r2.example.test',
      'VOICE_RECORDING_S3_FORCE_PATH_STYLE' => 'true'
    }
  end

  def create_same_account_unassigned_recording
    other_inbox = create(:channel_api, account: account).inbox
    other_conversation = create(:conversation, account: account, inbox: other_inbox)
    other_call = create(
      :call,
      conversation: other_conversation,
      account: account,
      inbox: other_inbox,
      contact: other_conversation.contact,
      provider: :livekit,
      status: 'completed'
    )
    create(:voice_recording, call: other_call, status: 'completed')
  end
end
