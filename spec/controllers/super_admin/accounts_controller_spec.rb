require 'rails_helper'

RSpec.describe 'Super Admin accounts API', type: :request do
  include ActiveJob::TestHelper

  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }

  describe 'GET /super_admin/accounts' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get '/super_admin/accounts'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'shows the list of accounts' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/accounts'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('New account')
        expect(response.body).to include(account.name)
      end
    end
  end

  describe 'POST /super_admin/accounts/{account_id}/reset_cache' do
    before do
      create(:label, account: account)
      create(:inbox, account: account)
      create(:team, account: account)
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/super_admin/accounts/#{account.id}/reset_cache"
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'shows the list of accounts' do
        expect(account.cache_keys.keys).to contain_exactly(:inbox, :label, :team)
        sign_in(super_admin, scope: :super_admin)

        now_timestamp = Time.now.utc.to_i
        post "/super_admin/accounts/#{account.id}/reset_cache"
        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to eq('Cache keys cleared')

        range = now_timestamp..(now_timestamp + 10)
        expect(account.reload.cache_keys.values.all? { |v| range.cover?(v.to_i) }).to be(true)
      end
    end
  end

  describe 'PATCH /super_admin/accounts/{account_id}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch "/super_admin/accounts/#{account.id}", params: { account: { name: 'New Name' } }
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'persists ai_agent_model and ai_agent_conversation_limit into settings' do
        sign_in(super_admin, scope: :super_admin)
        patch "/super_admin/accounts/#{account.id}", params: {
          account: {
            name: account.name,
            ai_agent_settings: {
              model: 'anthropic/claude-3.5-sonnet',
              conversation_limit: 100
            }
          }
        }

        expect(response).to have_http_status(:redirect)
        account.reload
        expect(account.ai_agent_model).to eq('anthropic/claude-3.5-sonnet')
        expect(account.ai_agent_conversation_limit).to eq(100)
      end

      it 'does not wipe existing settings keys when updating AI settings' do
        account.update!(settings: { auto_resolve_after: 30, auto_resolve_message: 'Hello' })
        sign_in(super_admin, scope: :super_admin)
        patch "/super_admin/accounts/#{account.id}", params: {
          account: {
            name: account.name,
            ai_agent_settings: {
              model: 'openai/gpt-4o-mini',
              conversation_limit: 25
            }
          }
        }

        expect(response).to have_http_status(:redirect)
        account.reload
        expect(account.settings['auto_resolve_after']).to eq(30)
        expect(account.settings['auto_resolve_message']).to eq('Hello')
        expect(account.ai_agent_model).to eq('openai/gpt-4o-mini')
        expect(account.ai_agent_conversation_limit).to eq(25)
      end
    end
  end

  describe 'DELETE /super_admin/accounts/{account_id}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/super_admin/accounts/#{account.id}"
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'Deletes the account' do
        total_accounts = Account.count
        sign_in(super_admin, scope: :super_admin)

        perform_enqueued_jobs(only: DeleteObjectJob) do
          delete "/super_admin/accounts/#{account.id}"
        end

        expect(Account.count).to eq(total_accounts - 1)
      end
    end
  end
end
