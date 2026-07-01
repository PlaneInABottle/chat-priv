require 'rails_helper'

RSpec.describe 'Super Admin Voice AI Calls', type: :request do
  let(:super_admin) { create(:super_admin) }

  it 'redirects unauthenticated users' do
    get '/super_admin/voice_ai_calls'

    expect(response).to have_http_status(:redirect)
  end

  it 'lists LiveKit calls for super admins' do
    call = create(:call, provider: :livekit, status: 'in_progress', meta: { 'test_call' => true, 'livekit_room_name' => 'room-test' })
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/voice_ai_calls'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Voice AI Calls', call.account.name, 'room-test')
  end

  it 'filters calls by account, status, test flag, and escaped room search' do
    matching = create(
      :call,
      provider: :livekit,
      status: 'completed',
      provider_call_id: 'call-room_%_literal',
      meta: { 'test_call' => true, 'livekit_room_name' => 'room_%_literal' }
    )
    same_account_attrs = {
      account: matching.account,
      inbox: matching.inbox,
      contact: matching.contact,
      conversation: matching.conversation,
      provider: :livekit,
      meta: { 'test_call' => true, 'livekit_room_name' => 'room_%_literal' }
    }
    wrong_status = create(:call, **same_account_attrs, status: 'in_progress', provider_call_id: 'wrong-status-room_%_literal')
    wrong_kind = create(
      :call,
      **same_account_attrs,
      status: 'completed',
      provider_call_id: 'wrong-kind-room_%_literal',
      meta: { 'test_call' => false, 'livekit_room_name' => 'room_%_literal' }
    )
    wildcard_nonmatch = create(
      :call,
      **same_account_attrs,
      status: 'completed',
      provider_call_id: 'wildcard-room-ab-literal',
      meta: { 'test_call' => true, 'livekit_room_name' => 'room-ab-literal' }
    )
    wrong_account = create(
      :call,
      provider: :livekit,
      status: 'completed',
      provider_call_id: 'wrong-account-room_%_literal',
      meta: { 'test_call' => true, 'livekit_room_name' => 'room_%_literal' }
    )
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/voice_ai_calls', params: {
      account_id: matching.account_id,
      status: 'completed',
      test_call: 'true',
      room: 'room_%'
    }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("/super_admin/voice_ai_calls/#{matching.id}")
    expect(response.body).not_to include("/super_admin/voice_ai_calls/#{wrong_status.id}")
    expect(response.body).not_to include("/super_admin/voice_ai_calls/#{wrong_kind.id}")
    expect(response.body).not_to include("/super_admin/voice_ai_calls/#{wildcard_nonmatch.id}")
    expect(response.body).not_to include("/super_admin/voice_ai_calls/#{wrong_account.id}")
  end

  it 'shows raw voice tool events, transcripts, and recordings for super admins' do
    call = create(:call, provider: :livekit, status: 'completed', meta: { 'livekit_room_name' => 'room-detail', 'voice_agent_id' => 123 })
    call.voice_tool_events.create!(
      account: call.account,
      tool: 'request_human_handoff',
      status: 'executed',
      arguments: { reason: 'private reason' },
      result: { internal_note: 'private note' },
      source: 'livekit_agent'
    )
    call.transcript_segments.create!(
      account: call.account,
      conversation: call.conversation,
      role: 'caller',
      source: 'livekit_agent',
      text: 'Merhaba'
    )
    call.voice_recordings.create!(
      account: call.account,
      status: 'completed',
      object_key: 'voice/calls/test.ogg',
      storage_provider: 's3_compatible'
    )
    sign_in(super_admin, scope: :super_admin)

    get "/super_admin/voice_ai_calls/#{call.id}"

    expect(response).to have_http_status(:success)
    expect(response.body).to include('request_human_handoff', 'private reason', 'private note', 'Merhaba', 'voice/calls/test.ogg')
    expect(response.body).to include('AI diagnostic summary', 'Download redacted JSON', 'View raw JSON')
  end

  it 'returns redacted diagnostics JSON by default' do
    call = create(:call, provider: :livekit, status: 'completed', meta: { 'livekit_room_name' => 'room-diagnostics' })
    call.transcript_segments.create!(
      account: call.account,
      conversation: call.conversation,
      role: 'caller',
      source: 'livekit_agent',
      text: 'Email test@example.com telefon +90 555 111 22 33'
    )
    sign_in(super_admin, scope: :super_admin)

    get "/super_admin/voice_ai_calls/#{call.id}/diagnostics.json"

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['redaction']).to include('mode' => 'redacted')
    expect(body['transcript_segments'].first['text']).to eq('Email [email redacted] telefon [phone redacted]')
    expect(body).to include('summary', 'failure_reasons', 'next_checks', 'timeline')
  end

  it 'returns raw diagnostics only when explicitly requested by a super admin' do
    call = create(:call, provider: :livekit, status: 'completed', meta: { 'livekit_room_name' => 'room-raw-diagnostics' })
    call.transcript_segments.create!(
      account: call.account,
      conversation: call.conversation,
      role: 'caller',
      source: 'livekit_agent',
      text: 'Email test@example.com telefon +90 555 111 22 33'
    )
    sign_in(super_admin, scope: :super_admin)

    allow(Rails.logger).to receive(:info).and_call_original
    get "/super_admin/voice_ai_calls/#{call.id}/diagnostics.json", params: { raw: true }

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['redaction']).to include('mode' => 'raw')
    expect(body['transcript_segments'].first['text']).to eq('Email test@example.com telefon +90 555 111 22 33')
    expect(Rails.logger).to have_received(:info).with(/raw voice diagnostics accessed call_id=#{call.id}/)
  end
end
