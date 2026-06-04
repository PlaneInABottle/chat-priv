require 'rails_helper'

RSpec.describe 'Ikas Integration API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    Integrations::Hook.name
    account.enable_features('ikas_integration')
    account.save!
  end

  def disable_ikas_feature!
    account.disable_features('ikas_integration')
    account.save!
  end

  describe 'GET /api/v1/accounts/:account_id/integrations/ikas' do
    it 'returns not_connected when no hook exists and encryption is available' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(true)

      get "/api/v1/accounts/#{account.id}/integrations/ikas", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['state']).to eq('not_connected')
      expect(response.parsed_body['can_connect']).to be true
    end

    it 'returns disabled when no hook exists and encryption is unavailable' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

      get "/api/v1/accounts/#{account.id}/integrations/ikas", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['state']).to eq('disabled')
      expect(response.parsed_body['can_connect']).to be false
    end

    it 'returns disabled when a hook exists but encryption is unavailable' do
      create(:integrations_hook, :ikas, account: account)
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

      get "/api/v1/accounts/#{account.id}/integrations/ikas", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['enabled']).to be true
      expect(response.parsed_body['state']).to eq('disabled')
      expect(response.parsed_body['can_connect']).to be false
      expect(response.parsed_body['can_disconnect']).to be true
    end

    it 'returns reconnect_required for malformed hooks' do
      hook = create(:integrations_hook, :ikas, account: account)
      hook.update_column(:access_token, nil)
      allow(Chatwoot).to receive(:encryption_configured?).and_return(true)

      get "/api/v1/accounts/#{account.id}/integrations/ikas", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['state']).to eq('reconnect_required')
      expect(response.parsed_body['last_validation_error_code']).to eq('malformed_hook')
    end

    it 'returns reconnect_required for duplicate hooks' do
      create(:integrations_hook, :ikas, account: account)
      build(:integrations_hook, :ikas, account: account).tap do |duplicate_hook|
        duplicate_hook.save!(validate: false)
      end
      allow(Chatwoot).to receive(:encryption_configured?).and_return(true)

      get "/api/v1/accounts/#{account.id}/integrations/ikas", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['state']).to eq('reconnect_required')
      expect(response.parsed_body['last_validation_error_code']).to eq('duplicate_hook')
    end

    it 'rejects non-admin users' do
      get "/api/v1/accounts/#{account.id}/integrations/ikas", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns not found when the feature is disabled' do
      disable_ikas_feature!

      get "/api/v1/accounts/#{account.id}/integrations/ikas", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq(I18n.t('errors.ikas.unavailable'))
    end
  end

  describe 'POST /api/v1/accounts/:account_id/integrations/ikas' do
    let(:payload) do
      {
        ikas: {
          client_id: 'client-id-1234',
          client_secret: 'client-secret-1234',
          store_url: 'https://test-store.myikas.com/'
        }
      }
    end

    before do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(true)
    end

    it 'creates a hook only after successful validation' do
      validator_result = Integrations::Ikas::ConnectionValidator::Result.new(
        success?: true,
        store_host: 'test-store.myikas.com',
        client_id: 'client-id-1234',
        client_secret: 'client-secret-1234',
        last_validated_at: '2026-05-07T12:34:56Z'
      )
      allow_any_instance_of(Integrations::Ikas::ConnectionValidator).to receive(:perform).and_return(validator_result)

      expect do
        post "/api/v1/accounts/#{account.id}/integrations/ikas", params: payload, headers: admin.create_new_auth_token, as: :json
      end.to change { account.hooks.where(app_id: 'ikas').count }.by(1)

      hook = account.hooks.find_by(app_id: 'ikas')
      expect(response).to have_http_status(:created)
      expect(hook.reference_id).to eq('test-store.myikas.com')
      expect(hook.settings['client_id']).to eq('client-id-1234')
      expect(hook.access_token).to eq('client-secret-1234')
      expect(response.body).not_to include('client-secret-1234')
      expect(response.parsed_body['store_url']).to eq('https://test-store.myikas.com')
      expect(response.parsed_body['catalog_sync']['status']).to eq('not_synced')
      expect(Integrations::Ikas::CatalogSyncJob).to have_been_enqueued.with(hook.id)
    end

    it 'does not persist invalid credentials' do
      validator_result = Integrations::Ikas::ConnectionValidator::Result.new(
        success?: false,
        error_code: 'auth_failed',
        error_message: 'Invalid credentials'
      )
      allow_any_instance_of(Integrations::Ikas::ConnectionValidator).to receive(:perform).and_return(validator_result)

      expect do
        post "/api/v1/accounts/#{account.id}/integrations/ikas", params: payload, headers: admin.create_new_auth_token, as: :json
      end.not_to change { account.hooks.where(app_id: 'ikas').count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['last_validation_error_code']).to eq('auth_failed')
    end

    it 'returns disabled behavior when encryption is unavailable' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

      post "/api/v1/accounts/#{account.id}/integrations/ikas", params: payload, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['last_validation_error_code']).to eq('encryption_unavailable')
    end

    it 'returns not found when the feature is disabled' do
      disable_ikas_feature!

      post "/api/v1/accounts/#{account.id}/integrations/ikas", params: payload, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq(I18n.t('errors.ikas.unavailable'))
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/integrations/ikas' do
    let!(:hook) { create(:integrations_hook, :ikas, account: account, access_token: 'persisted-secret') }

    before do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(true)
    end

    it 'preserves the existing secret when the update secret is blank' do
      validator_result = Integrations::Ikas::ConnectionValidator::Result.new(
        success?: true,
        store_host: 'test-store.myikas.com',
        client_id: 'updated-client-id',
        client_secret: 'persisted-secret',
        last_validated_at: '2026-05-07T12:34:56Z'
      )
      allow_any_instance_of(Integrations::Ikas::ConnectionValidator).to receive(:perform).and_return(validator_result)

      patch "/api/v1/accounts/#{account.id}/integrations/ikas",
            params: { ikas: { client_id: 'updated-client-id', client_secret: '', store_url: 'https://test-store.myikas.com' } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(hook.reload.access_token).to eq('persisted-secret')
      expect(hook.settings['client_id']).to eq('updated-client-id')
    end

    it 'allows reconnecting malformed hooks' do
      hook.update!(access_token: nil)

      validator_result = Integrations::Ikas::ConnectionValidator::Result.new(
        success?: true,
        store_host: 'test-store.myikas.com',
        client_id: 'updated-client-id',
        client_secret: 'replacement-secret',
        last_validated_at: '2026-05-07T12:34:56Z'
      )
      allow_any_instance_of(Integrations::Ikas::ConnectionValidator).to receive(:perform).and_return(validator_result)

      patch "/api/v1/accounts/#{account.id}/integrations/ikas",
            params: { ikas: { client_id: 'updated-client-id', client_secret: 'replacement-secret', store_url: 'https://test-store.myikas.com' } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(hook.reload.access_token).to eq('replacement-secret')
      expect(response.parsed_body['state']).to eq('connected')
    end

    it 'keeps the existing hook unchanged on validation failure' do
      validator_result = Integrations::Ikas::ConnectionValidator::Result.new(
        success?: false,
        error_code: 'probe_failed',
        error_message: 'Probe failed'
      )
      allow_any_instance_of(Integrations::Ikas::ConnectionValidator).to receive(:perform).and_return(validator_result)

      patch "/api/v1/accounts/#{account.id}/integrations/ikas",
            params: { ikas: { client_id: 'updated-client-id', client_secret: 'new-secret', store_url: 'https://test-store.myikas.com' } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(hook.reload.settings['client_id']).to eq('client-id-1234')
      expect(hook.access_token).to eq('persisted-secret')
    end

    it 'returns not found when the feature is disabled' do
      disable_ikas_feature!

      patch "/api/v1/accounts/#{account.id}/integrations/ikas",
            params: { ikas: { client_id: 'updated-client-id', client_secret: 'new-secret', store_url: 'https://test-store.myikas.com' } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq(I18n.t('errors.ikas.unavailable'))
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/integrations/ikas' do
    let!(:hook) { create(:integrations_hook, :ikas, account: account) }

    it 'removes the ikas hook' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(true)

      expect do
        delete "/api/v1/accounts/#{account.id}/integrations/ikas", headers: admin.create_new_auth_token, as: :json
      end.to change { account.hooks.where(app_id: 'ikas').count }.by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['state']).to eq('not_connected')
    end

    it 'returns not found when the feature is disabled' do
      disable_ikas_feature!

      delete "/api/v1/accounts/#{account.id}/integrations/ikas", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq(I18n.t('errors.ikas.unavailable'))
    end
  end

  describe 'POST /api/v1/accounts/:account_id/integrations/ikas/catalog_sync' do
    let!(:hook) { create(:integrations_hook, :ikas, account: account) }

    it 'enqueues a catalog sync for the connected hook' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(true)

      post "/api/v1/accounts/#{account.id}/integrations/ikas/catalog_sync", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['catalog_sync']['status']).to eq('not_synced')
      expect(Integrations::Ikas::CatalogSyncJob).to have_been_enqueued.with(hook.id)
    end

    it 'does not enqueue a catalog sync when encryption is unavailable' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

      post "/api/v1/accounts/#{account.id}/integrations/ikas/catalog_sync", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['last_validation_error_code']).to eq('encryption_unavailable')
      expect(Integrations::Ikas::CatalogSyncJob).not_to have_been_enqueued
    end
  end
end
