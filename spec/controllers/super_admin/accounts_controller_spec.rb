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

  describe 'GET /super_admin/accounts/{account_id}' do
    context 'when it is an authenticated user' do
      it 'shows effective Captain model routing', if: ChatwootApp.enterprise? do
        account.update!(captain_models: { 'editor' => 'gpt-4.1' })
        sign_in(super_admin, scope: :super_admin)

        get "/super_admin/accounts/#{account.id}"
        document = Nokogiri::HTML(response.body)
        summaries = document.css('details summary').map { |summary| summary.text.squish }

        expect(response).to have_http_status(:success)
        expect(document.at_css('#captain_models').text.squish).to eq('Captain models')
        expect(summaries).to include('View model routing')
        expect(summaries).not_to include('All features')
        expect(summaries).not_to include('Captain models')
        expect(response.body).to include('Editor', 'OpenAI', 'openai', 'gpt-4.1', 'Account override', 'Label suggestion', 'Default')
      end
    end
  end

  describe 'GET /super_admin/accounts/{account_id}/edit' do
    context 'when it is an authenticated user' do
      it 'renders a Captain model selector for every AI feature', if: ChatwootApp.enterprise? do
        account.update!(captain_models: { 'editor' => 'gpt-4.1' })
        sign_in(super_admin, scope: :super_admin)

        get "/super_admin/accounts/#{account.id}/edit"

        expect(response).to have_http_status(:success)
        Llm::Models.feature_keys.each do |feature_key|
          expect(response.body).to include("account[captain_models][#{feature_key}]")
        end

        document = Nokogiri::HTML(response.body)
        editor_select = document.at_css('select[name="account[captain_models][editor]"]')
        default_model_id = Llm::Models.default_model_for('editor')
        default_model = Llm::Models.model_config(default_model_id)['display_name']

        expect(editor_select.at_css('option[value=""]').text.squish).to eq("Use default: #{default_model} (#{default_model_id})")
      end

      it 'shows the Captain V2 assistant default in the model selector', if: ChatwootApp.enterprise? do
        account.enable_features!('captain_integration_v2')
        sign_in(super_admin, scope: :super_admin)

        get "/super_admin/accounts/#{account.id}/edit"

        document = Nokogiri::HTML(response.body)
        assistant_select = document.at_css('select[name="account[captain_models][assistant]"]')
        default_model_id = Llm::FeatureRouter::CAPTAIN_V2_ASSISTANT_MODEL
        default_model = Llm::Models.model_config(default_model_id)['display_name']

        expect(response).to have_http_status(:success)
        expect(assistant_select.at_css('option[value=""]').text.squish).to eq("Use default: #{default_model} (#{default_model_id})")
      end
    end
  end

  describe 'PATCH /super_admin/accounts/{account_id}' do
    context 'when it is an authenticated user' do
      it 'updates Captain model overrides without changing unrelated settings' do
        account.update!(
          captain_models: { 'editor' => 'gpt-4.1' },
          keep_pending_on_bot_failure: true
        )
        sign_in(super_admin, scope: :super_admin)

        patch "/super_admin/accounts/#{account.id}",
              params: {
                account: {
                  name: account.name,
                  locale: account.locale,
                  status: account.status,
                  captain_models: {
                    editor: '',
                    assistant: 'gpt-5.2'
                  }
                }
              }

        expect(response).to have_http_status(:redirect)
        expect(account.reload.captain_models).to eq('assistant' => 'gpt-5.2')
        expect(account.keep_pending_on_bot_failure).to be true
      end

      it 'rejects invalid Captain model overrides' do
        sign_in(super_admin, scope: :super_admin)
        existing_captain_models = account.captain_models

        patch "/super_admin/accounts/#{account.id}",
              params: {
                account: {
                  name: account.name,
                  locale: account.locale,
                  status: account.status,
                  captain_models: {
                    label_suggestion: 'gpt-5.1'
                  }
                }
              }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('not a valid model for label_suggestion')
        expect(account.reload.captain_models).to eq(existing_captain_models)
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
              conversation_reuse_window_hours: 48,
              data_retention_days: 90
            }
          }
        }

        expect(response).to have_http_status(:redirect)
        account.reload
        expect(account.ai_agent_enabled?).to be(true)
        expect(account.ai_agent_model).to eq('anthropic/claude-3.5-sonnet')
        expect(account.ai_agent_conversation_limit).to eq(100)
        expect(account.ai_agent_conversation_reuse_window_hours).to eq(48)
        expect(account.ai_agent_data_retention_days).to eq(90)
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

      it 'persists Voice AI account limit settings into account settings' do
        sign_in(super_admin, scope: :super_admin)
        patch "/super_admin/accounts/#{account.id}", params: {
          account: {
            name: account.name,
            voice_ai_settings: {
              enabled: 'true',
              monthly_minute_limit: 120,
              max_call_duration_minutes: 20,
              concurrent_call_limit: 3,
              data_retention_days: 180
            }
          }
        }

        expect(response).to have_http_status(:redirect)
        account.reload
        expect(account.voice_ai_enabled?).to be(true)
        expect(account.voice_ai_monthly_minute_limit).to eq(120)
        expect(account.voice_ai_max_call_duration_minutes).to eq(20)
        expect(account.voice_ai_concurrent_call_limit).to eq(3)
        expect(account.voice_ai_data_retention_days).to eq(180)
      end

      context 'with AI quota limits' do
        it 'persists explicit zero conversation limit as unlimited' do
          sign_in(super_admin, scope: :super_admin)

          patch "/super_admin/accounts/#{account.id}", params: {
            account: { name: account.name, ai_agent_settings: { conversation_limit: '0' } }
          }

          expect(response).to have_http_status(:redirect)
          expect(account.reload.ai_agent_conversation_limit).to eq(0)
        end

        it 'persists explicit zero workspace credit limit as unlimited' do
          sign_in(super_admin, scope: :super_admin)

          patch "/super_admin/accounts/#{account.id}", params: {
            account: { name: account.name, ai_improvement_settings: { monthly_credit_limit: '0' } }
          }

          expect(response).to have_http_status(:redirect)
          expect(account.reload.ai_improvement_monthly_credit_limit).to eq(0)
        end

        it 'updates conversation and workspace credit limits independently' do
          account.update!(ai_agent_conversation_limit: 100, ai_improvement_monthly_credit_limit: 600)
          sign_in(super_admin, scope: :super_admin)

          patch "/super_admin/accounts/#{account.id}", params: {
            account: { name: account.name, ai_agent_settings: { conversation_limit: 100 } }
          }

          expect(response).to have_http_status(:redirect)
          account.reload
          expect(account.ai_agent_conversation_limit).to eq(100)
          expect(account.ai_improvement_monthly_credit_limit).to eq(600)

          patch "/super_admin/accounts/#{account.id}", params: {
            account: { name: account.name, ai_improvement_settings: { monthly_credit_limit: 300 } }
          }

          expect(response).to have_http_status(:redirect)
          account.reload
          expect(account.ai_improvement_monthly_credit_limit).to eq(300)
          expect(account.ai_agent_conversation_limit).to eq(100)
        end

        it 'applies a lowered conversation limit immediately without rewriting usage events' do
          period = AiAgents::Usage::Period.new(account: account, now: Time.current)
          account.update!(ai_agent_enabled: true, ai_agent_conversation_limit: 100)
          create_list(:ai_agent_usage_event, 50, account: account, status: :consumed, period_start_at: period.start_at,
                                                 period_end_at: period.end_at)
          sign_in(super_admin, scope: :super_admin)

          expect(AiAgents::Usage::Summary.new(account: account).payload[:remaining]).to eq(50)

          patch "/super_admin/accounts/#{account.id}", params: {
            account: { name: account.name, ai_agent_settings: { conversation_limit: 10 } }
          }

          expect(response).to have_http_status(:redirect)
          account.reload
          expect(account.ai_agent_conversation_limit).to eq(10)
          expect(account.ai_agent_usage_events.count).to eq(50)

          summary = AiAgents::Usage::Summary.new(account: account).payload
          expect(summary[:remaining]).to eq(0)
          expect(summary[:status]).to eq('exhausted')
        end

        it 'applies a raised conversation limit immediately without rewriting usage events' do
          period = AiAgents::Usage::Period.new(account: account, now: Time.current)
          account.update!(ai_agent_enabled: true, ai_agent_conversation_limit: 100)
          create_list(:ai_agent_usage_event, 50, account: account, status: :consumed, period_start_at: period.start_at,
                                                 period_end_at: period.end_at)
          sign_in(super_admin, scope: :super_admin)

          patch "/super_admin/accounts/#{account.id}", params: {
            account: { name: account.name, ai_agent_settings: { conversation_limit: 200 } }
          }

          expect(response).to have_http_status(:redirect)
          account.reload
          expect(account.ai_agent_conversation_limit).to eq(200)
          expect(account.ai_agent_usage_events.count).to eq(50)
          expect(AiAgents::Usage::Summary.new(account: account).payload[:remaining]).to eq(150)
        end

        it 'applies a lowered workspace credit limit immediately without rewriting usage events' do
          period = AiAgents::Usage::Period.new(account: account, now: Time.current)
          account.update!(ai_improvement_monthly_credit_limit: 600)
          AiImprovementUsageEvent.create!(
            account: account, operation: 'text_test', unit_type: 'tokens', units: 10_000, credits: 300,
            status: :consumed, period_start_at: period.start_at, period_end_at: period.end_at,
            idempotency_key: "super-admin-credit-seed-#{account.id}"
          )
          sign_in(super_admin, scope: :super_admin)

          expect(AiImprovements::Usage::Summary.new(account: account).payload[:remaining_credits]).to eq(300)

          patch "/super_admin/accounts/#{account.id}", params: {
            account: { name: account.name, ai_improvement_settings: { monthly_credit_limit: 100 } }
          }

          expect(response).to have_http_status(:redirect)
          account.reload
          expect(account.ai_improvement_monthly_credit_limit).to eq(100)
          expect(account.ai_improvement_usage_events.sum(:credits)).to eq(300)

          summary = AiImprovements::Usage::Summary.new(account: account)
          expect(summary.payload[:remaining_credits]).to eq(0)
          expect(summary.exhausted?).to be(true)
        end

        it 'applies a raised workspace credit limit immediately without rewriting usage events' do
          period = AiAgents::Usage::Period.new(account: account, now: Time.current)
          account.update!(ai_improvement_monthly_credit_limit: 600)
          AiImprovementUsageEvent.create!(
            account: account, operation: 'text_test', unit_type: 'tokens', units: 10_000, credits: 300,
            status: :consumed, period_start_at: period.start_at, period_end_at: period.end_at,
            idempotency_key: "super-admin-credit-seed-#{account.id}"
          )
          sign_in(super_admin, scope: :super_admin)

          patch "/super_admin/accounts/#{account.id}", params: {
            account: { name: account.name, ai_improvement_settings: { monthly_credit_limit: 500 } }
          }

          expect(response).to have_http_status(:redirect)
          account.reload
          expect(account.ai_improvement_monthly_credit_limit).to eq(500)
          expect(account.ai_improvement_usage_events.sum(:credits)).to eq(300)
          expect(AiImprovements::Usage::Summary.new(account: account).payload[:remaining_credits]).to eq(200)
        end
      end

      it 'persists voice agent runtime settings' do
        voice_agent = create(:voice_agent, account: account, architecture: 'realtime', provider: 'gemini', voice: 'Charon', language: 'tr')
        sign_in(super_admin, scope: :super_admin)

        patch "/super_admin/accounts/#{account.id}", params: {
          account: {
            name: account.name,
            voice_agent_runtime_settings: {
              voice_agent.id => {
                architecture: 'realtime',
                provider: 'openai',
                model: 'gpt-realtime-2.1',
                voice: 'marin',
                language: 'tr'
              }
            }
          }
        }

        expect(response).to have_http_status(:redirect)
        expect(voice_agent.reload).to have_attributes(
          architecture: 'realtime',
          provider: 'openai',
          model: 'gpt-realtime-2.1',
          voice: 'marin',
          language: 'tr'
        )
      end
    end
  end

  describe 'POST /super_admin/accounts/{account_id}/purge_ai_data' do
    it 'redirects unauthenticated users without queueing cleanup' do
      expect do
        post "/super_admin/accounts/#{account.id}/purge_ai_data", params: { kind: 'text' }
      end.not_to have_enqueued_job(AiDataRetention::PurgeAccountJob)

      expect(response).to have_http_status(:redirect)
    end

    it 'queues cleanup for a valid AI mode' do
      sign_in(super_admin, scope: :super_admin)

      expect do
        post "/super_admin/accounts/#{account.id}/purge_ai_data", params: { kind: 'voice' }
      end.to have_enqueued_job(AiDataRetention::PurgeAccountJob).with(account.id, 'voice')

      expect(response).to redirect_to(super_admin_account_path(account))
      expect(flash[:notice]).to eq('Voice AI data cleanup queued.')
    end

    it 'rejects unsupported cleanup modes' do
      sign_in(super_admin, scope: :super_admin)

      expect do
        post "/super_admin/accounts/#{account.id}/purge_ai_data", params: { kind: 'all' }
      end.not_to have_enqueued_job(AiDataRetention::PurgeAccountJob)

      expect(response).to redirect_to(super_admin_account_path(account))
      expect(flash[:alert]).to eq('AI data cleanup must target Text or Voice.')
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
