require 'rails_helper'

RSpec.describe 'Super Admin voice provider connections', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }

  it 'redirects unauthenticated users' do
    get '/super_admin/voice_provider_connections'

    expect(response).to have_http_status(:redirect)
  end

  it 'lists provider connections for super admins' do
    connection = create(:voice_provider_connection, account: account, name: 'Local SIP')
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/voice_provider_connections'

    expect(response).to have_http_status(:success)
    expect(response.body).to include(connection.name)
  end

  it 'creates a provider connection without accepting raw JSON settings' do
    sign_in(super_admin, scope: :super_admin)

    expect do
      post '/super_admin/voice_provider_connections',
           params: {
             voice_provider_connection: {
               account_id: account.id,
               provider: 'test_sip',
               name: 'Local SIP',
               status: 'active',
               settings: '{"sip_domain":"local.test","port":5060}'
             }
           }
    end.to change(VoiceProviderConnection, :count).by(1)

    connection = VoiceProviderConnection.last
    expect(connection).to have_attributes(account: account, provider: 'test_sip', name: 'Local SIP', status: 'active')
    expect(connection.settings).to eq({})
  end

  it 'ignores invalid settings JSON submitted outside the form' do
    sign_in(super_admin, scope: :super_admin)

    post '/super_admin/voice_provider_connections',
         params: {
           voice_provider_connection: {
             account_id: account.id,
             provider: 'manual_sip',
             name: 'Manual SIP',
             status: 'draft',
             settings: '{invalid-json'
           }
         }

    expect(response).to have_http_status(:redirect)
    expect(VoiceProviderConnection.last.settings).to eq({})
  end

  it 'redacts secret-like settings on the show page' do
    connection = create(
      :voice_provider_connection,
      account: account,
      settings: {
        'sip_domain' => 'local.test',
        'password' => 'super-secret',
        'api_key' => 'provider-key'
      }
    )
    sign_in(super_admin, scope: :super_admin)

    get "/super_admin/voice_provider_connections/#{connection.id}"

    expect(response).to have_http_status(:success)
    expect(response.body).to include('local.test', '[redacted]')
    expect(response.body).not_to include('super-secret', 'provider-key')
  end
end
