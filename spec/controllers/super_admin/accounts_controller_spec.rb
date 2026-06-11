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

    after do
      Conversations::UnreadCounts::Store.clear_account!(account.id)
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

      it 'clears conversation unread count cache' do
        inbox = account.inboxes.first
        store = Conversations::UnreadCounts::Store
        inbox_key = store.inbox_key(account.id, inbox.id)
        store.mark_base_ready!(account.id)
        store.add_base_membership(account_id: account.id, inbox_id: inbox.id, label_ids: [], conversation_id: 1)

        sign_in(super_admin, scope: :super_admin)
        post "/super_admin/accounts/#{account.id}/reset_cache"

        expect(response).to have_http_status(:redirect)
        expect(store.base_ready?(account.id)).to be(false)
        expect(store.counts_for_keys([inbox_key])).to eq(inbox_key => 0)
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
      it 'persists AI Agent settings into account settings' do
        sign_in(super_admin, scope: :super_admin)
        patch "/super_admin/accounts/#{account.id}", params: {
          account: {
            name: account.name,
            ai_agent_settings: {
              enabled: 'true',
              model: 'anthropic/claude-3.5-sonnet',
              conversation_limit: 100,
              conversation_reuse_window_hours: 48
            }
          }
        }

        expect(response).to have_http_status(:redirect)
        account.reload
        expect(account.ai_agent_enabled?).to be(true)
        expect(account.ai_agent_model).to eq('anthropic/claude-3.5-sonnet')
        expect(account.ai_agent_conversation_limit).to eq(100)
        expect(account.ai_agent_conversation_reuse_window_hours).to eq(48)
      end

      it 'does not wipe existing settings keys when updating AI settings' do
        account.update!(settings: { auto_resolve_after: 30, auto_resolve_message: 'Hello' })
        sign_in(super_admin, scope: :super_admin)
        patch "/super_admin/accounts/#{account.id}", params: {
          account: {
            name: account.name,
            ai_agent_settings: {
              enabled: 'false',
              model: 'openai/gpt-4o-mini',
              conversation_limit: 25,
              conversation_reuse_window_hours: 12
            }
          }
        }

        expect(response).to have_http_status(:redirect)
        account.reload
        expect(account.settings['auto_resolve_after']).to eq(30)
        expect(account.settings['auto_resolve_message']).to eq('Hello')
        expect(account.ai_agent_enabled?).to be(false)
        expect(account.ai_agent_model).to eq('openai/gpt-4o-mini')
        expect(account.ai_agent_conversation_limit).to eq(25)
        expect(account.ai_agent_conversation_reuse_window_hours).to eq(12)
      end

      it 'persists voice agent runtime settings' do
        voice_agent = create(:voice_agent, account: account, architecture: 'realtime', provider: 'gemini', voice: 'Charon', language: 'tr')
        sign_in(super_admin, scope: :super_admin)

        patch "/super_admin/accounts/#{account.id}", params: {
          account: {
            name: account.name,
            voice_agent_runtime_settings: {
              voice_agent.id => {
                architecture: 'pipeline',
                provider: 'openai',
                model: 'gpt-4o-realtime-preview',
                voice: 'alloy',
                language: 'en'
              }
            }
          }
        }

        expect(response).to have_http_status(:redirect)
        expect(voice_agent.reload).to have_attributes(
          architecture: 'pipeline',
          provider: 'openai',
          model: 'gpt-4o-realtime-preview',
          voice: 'alloy',
          language: 'en'
        )
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
