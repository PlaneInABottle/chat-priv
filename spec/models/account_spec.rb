# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Account do
  it { is_expected.to have_many(:users).through(:account_users) }
  it { is_expected.to have_many(:account_users) }
  it { is_expected.to have_many(:inboxes).dependent(:destroy_async) }
  it { is_expected.to have_many(:conversations).dependent(:destroy_async) }
  it { is_expected.to have_many(:contacts).dependent(:destroy_async) }
  it { is_expected.to have_many(:canned_responses).dependent(:destroy_async) }
  it { is_expected.to have_many(:facebook_pages).class_name('::Channel::FacebookPage').dependent(:destroy_async) }
  it { is_expected.to have_many(:web_widgets).class_name('::Channel::WebWidget').dependent(:destroy_async) }
  it { is_expected.to have_many(:webhooks).dependent(:destroy_async) }
  it { is_expected.to have_many(:voice_agents).dependent(:destroy) }
  it { is_expected.to have_many(:voice_provider_connections).dependent(:destroy) }
  it { is_expected.to have_many(:voice_numbers).dependent(:destroy) }
  it { is_expected.to have_many(:notification_settings).dependent(:destroy_async) }
  it { is_expected.to have_many(:reporting_events) }
  it { is_expected.to have_many(:portals).dependent(:destroy_async) }
  it { is_expected.to have_many(:categories).dependent(:destroy_async) }
  it { is_expected.to have_many(:teams).dependent(:destroy_async) }

  # This validation happens in ApplicationRecord
  describe 'length validations' do
    let(:account) { create(:account) }

    it 'validates name presence' do
      account.name = ''
      account.valid?
      expect(account.errors[:name]).to include("can't be blank")
    end

    it 'validates name length' do
      account.name = 'a' * 256
      account.valid?
      expect(account.errors[:name]).to include('is too long (maximum is 255 characters)')
    end

    it 'validates domain length' do
      account.domain = 'a' * 150
      account.valid?
      expect(account.errors[:domain]).to include('is too long (maximum is 100 characters)')
    end
  end

  describe 'usage_limits' do
    let(:account) { create(:account) }

    it 'returns ChatwootApp.max limits' do
      expect(account.usage_limits[:agents]).to eq(ChatwootApp.max_limit)
      expect(account.usage_limits[:inboxes]).to eq(ChatwootApp.max_limit)
    end
  end

  describe '#api_and_webhooks_enabled?' do
    it 'is enabled for self-hosted accounts regardless of the stored feature flag' do
      account = create(:account)
      account.disable_features!('api_and_webhooks')

      expect(account.api_and_webhooks_enabled?).to be true
    end
  end

  describe 'captain defaults for new accounts' do
    it 'does not store Captain model overrides or enable premium Captain features' do
      InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').update!(
        value: Featurable::FEATURE_LIST,
        locked: true
      )

      account = create(:account)

      expect(account).not_to be_feature_enabled('captain_integration')
      expect(account).not_to be_feature_enabled('captain_integration_v2')
      expect(account.captain_models).to be_nil
    end
  end

  describe 'voice agent defaults' do
    it 'creates one default voice agent when the account is created' do
      account = create(:account)

      expect(account.voice_agents.count).to eq(1)
      expect(account.voice_agents.first).to have_attributes(
        name: 'Voice Assistant',
        enabled: true,
        language: 'tr',
        voice: 'Charon'
      )
      expect(account.voice_agents.first.tools_config['enabled']).to include('human_handoff', 'end_customer_call')
    end

    it 'does not create duplicate default voice agents' do
      account = create(:account)

      expect { account.create_default_voice_agent! }.not_to change { account.voice_agents.count }
    end
  end

  describe 'conversation unread counts feature flag' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:store) { Conversations::UnreadCounts::Store }
    let(:inbox_key) { store.inbox_key(account.id, inbox.id) }

    after do
      store.clear_account!(account.id)
    end

    it 'clears unread count cache when the feature is enabled' do
      build_unread_count_cache

      account.enable_features!(:conversation_unread_counts)

      expect(store.base_ready?(account.id)).to be(false)
      expect(store.assignment_ready?(account.id)).to be(false)
      expect(store.counts_for_keys([inbox_key])).to eq(inbox_key => 0)
    end

    it 'clears unread count cache when the feature is disabled' do
      account.enable_features!(:conversation_unread_counts)
      build_unread_count_cache

      account.disable_features!(:conversation_unread_counts)

      expect(store.base_ready?(account.id)).to be(false)
      expect(store.assignment_ready?(account.id)).to be(false)
      expect(store.counts_for_keys([inbox_key])).to eq(inbox_key => 0)
    end

    def build_unread_count_cache
      store.mark_base_ready!(account.id)
      store.mark_assignment_ready!(account.id)
      store.add_base_membership(account_id: account.id, inbox_id: inbox.id, label_ids: [], conversation_id: 1)
    end
  end

  describe 'feature flag columns' do
    let(:account) { described_class.new(name: 'Test Account') }

    it 'configures the account feature flag extension column' do
      expect(described_class.flag_columns).to include('feature_flags', 'feature_flags_ext_1')
      expect(described_class.flag_mapping['feature_flags_ext_1']).to eq(
        feature_whatsapp_manual_transfer: 1,
        feature_data_import: 1 << 1,
        feature_api_and_webhooks: 1 << 2,
        feature_whatsapp_reconfigure: 1 << 3,
        feature_whatsapp_embedded_signup_inbox_creation: 1 << 4
      )
      expect(described_class.flag_mapping['feature_flags_ext_1'][:feature_whatsapp_manual_transfer]).to eq(1)
      expect(described_class.flag_mapping['feature_flags_ext_1'][:feature_data_import]).to eq(2)
      expect(described_class.flag_mapping['feature_flags_ext_1'][:feature_whatsapp_embedded_signup_inbox_creation]).to eq(16)
    end

    it 'keeps existing feature flags on the original column' do
      expect(described_class.flag_mapping['feature_flags'][:feature_inbound_emails]).to eq(1)
      expect(described_class.flag_mapping['feature_flags'][:feature_advanced_assignment]).to eq(1 << 62)
    end

    it 'keeps bulk selected feature assignment compatible with existing feature names' do
      account.selected_feature_flags = [:feature_ip_lookup, :feature_assignment_v2, :feature_advanced_assignment, :feature_data_import]

      expect(account).to be_feature_ip_lookup
      expect(account).to be_feature_assignment_v2
      expect(account).to be_feature_advanced_assignment
      expect(account).to be_feature_data_import
      expect(account.selected_feature_flags).to contain_exactly(
        :feature_ip_lookup,
        :feature_assignment_v2,
        :feature_advanced_assignment,
        :feature_data_import
      )
    end
  end

  describe 'inbound_email_domain' do
    let(:account) { create(:account) }

    it 'returns the domain from inbox if inbox value is present' do
      account.update(domain: 'test.com')
      with_modified_env MAILER_INBOUND_EMAIL_DOMAIN: 'test2.com' do
        expect(account.inbound_email_domain).to eq('test.com')
      end
    end

    it 'returns the domain from ENV if inbox value is nil' do
      account.update(domain: nil)
      with_modified_env MAILER_INBOUND_EMAIL_DOMAIN: 'test.com' do
        expect(account.inbound_email_domain).to eq('test.com')
      end
    end

    it 'returns the domain from ENV if inbox value is empty string' do
      account.update(domain: '')
      with_modified_env MAILER_INBOUND_EMAIL_DOMAIN: 'test.com' do
        expect(account.inbound_email_domain).to eq('test.com')
      end
    end
  end

  describe 'support_email' do
    let(:account) { create(:account) }

    it 'returns the support email from inbox if inbox value is present' do
      account.update(support_email: 'support@chatwoot.com')
      with_modified_env MAILER_SENDER_EMAIL: 'hello@chatwoot.com' do
        expect(account.support_email).to eq('support@chatwoot.com')
      end
    end

    it 'returns the support email from ENV if inbox value is nil' do
      account.update(support_email: nil)
      with_modified_env MAILER_SENDER_EMAIL: 'hello@chatwoot.com' do
        expect(account.support_email).to eq('hello@chatwoot.com')
      end
    end

    it 'returns the support email from ENV if inbox value is empty string' do
      account.update(support_email: '')
      with_modified_env MAILER_SENDER_EMAIL: 'hello@chatwoot.com' do
        expect(account.support_email).to eq('hello@chatwoot.com')
      end
    end
  end

  context 'when after_destroy is called' do
    it 'conv_dpid_seq and camp_dpid_seq_ are deleted' do
      account = create(:account)
      query = "select * from information_schema.sequences where sequence_name in  ('camp_dpid_seq_#{account.id}', 'conv_dpid_seq_#{account.id}');"
      expect(ActiveRecord::Base.connection.execute(query).count).to eq(2)
      expect(account.locale).to eq('en')
      account.destroy
      expect(ActiveRecord::Base.connection.execute(query).count).to eq(0)
    end
  end

  describe 'locale' do
    it 'returns correct language if the value is set' do
      account = create(:account, locale: 'fr')
      expect(account.locale).to eq('fr')
      expect(account.locale_english_name).to eq('french')
    end

    it 'returns english if the value is not set' do
      account = create(:account, locale: nil)
      expect(account.locale).to be_nil
      expect(account.locale_english_name).to eq('english')
    end

    it 'returns english if the value is empty string' do
      account = create(:account, locale: '')
      expect(account.locale).to be_nil
      expect(account.locale_english_name).to eq('english')
    end

    it 'returns correct language if the value has country code' do
      account = create(:account, locale: 'pt_BR')
      expect(account.locale).to eq('pt_BR')
      expect(account.locale_english_name).to eq('portuguese')
    end
  end

  describe 'settings' do
    let(:account) { create(:account) }

    context 'when auto_resolve_after' do
      it 'validates minimum value' do
        account.settings = { auto_resolve_after: 4 }
        expect(account).to be_invalid
        expect(account.errors.messages).to eq({ auto_resolve_after: ['must be greater than or equal to 10'] })
      end

      it 'validates maximum value' do
        account.settings = { auto_resolve_after: 1_439_857 }
        expect(account).to be_invalid
        expect(account.errors.messages).to eq({ auto_resolve_after: ['must be less than or equal to 1439856'] })
      end

      it 'allows valid values' do
        account.settings = { auto_resolve_after: 15 }
        expect(account).to be_valid

        account.settings = { auto_resolve_after: 1_439_856 }
        expect(account).to be_valid
      end

      it 'allows null values' do
        account.settings = { auto_resolve_after: nil }
        expect(account).to be_valid
      end
    end

    context 'when auto_resolve_message' do
      it 'allows string values' do
        account.settings = { auto_resolve_message: 'This conversation has been resolved automatically.' }
        expect(account).to be_valid
      end

      it 'allows empty string' do
        account.settings = { auto_resolve_message: '' }
        expect(account).to be_valid
      end

      it 'allows nil values' do
        account.settings = { auto_resolve_message: nil }
        expect(account).to be_valid
      end
    end

    context 'when using store_accessor' do
      it 'correctly gets and sets auto_resolve_after' do
        account.auto_resolve_after = 30
        expect(account.auto_resolve_after).to eq(30)
        expect(account.settings['auto_resolve_after']).to eq(30)
      end

      it 'correctly gets and sets auto_resolve_message' do
        message = 'This conversation was automatically resolved'
        account.auto_resolve_message = message
        expect(account.auto_resolve_message).to eq(message)
        expect(account.settings['auto_resolve_message']).to eq(message)
      end

      it 'defaults captain_auto_resolve_mode to legacy when captain_tasks is disabled' do
        allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(false)

        expect(account.captain_auto_resolve_mode).to eq('legacy')
        expect(account).to be_captain_auto_resolve_legacy
      end

      it 'defaults captain_auto_resolve_mode to evaluated when captain_tasks is enabled' do
        allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)

        expect(account.captain_auto_resolve_mode).to eq('evaluated')
        expect(account).to be_captain_auto_resolve_evaluated
      end

      it 'correctly gets and sets captain_auto_resolve_mode' do
        account.captain_auto_resolve_mode = 'legacy'

        expect(account.captain_auto_resolve_mode).to eq('legacy')
        expect(account.settings['captain_auto_resolve_mode']).to eq('legacy')
        expect(account).to be_captain_auto_resolve_legacy
      end

      it 'allows clearing captain_auto_resolve_mode to fall back to feature defaults' do
        allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(false)
        account.captain_auto_resolve_mode = nil

        expect(account).to be_valid
        expect(account.captain_auto_resolve_mode).to eq('legacy')
        expect(account.settings['captain_auto_resolve_mode']).to be_nil
      end

      it 'falls back to disabled mode from legacy settings key' do
        account.settings = { 'captain_disable_auto_resolve' => true }

        expect(account.captain_auto_resolve_mode).to eq('disabled')
        expect(account).to be_captain_auto_resolve_disabled
      end

      it 'handles nil values correctly' do
        account.auto_resolve_after = nil
        account.auto_resolve_message = nil
        expect(account.auto_resolve_after).to be_nil
        expect(account.auto_resolve_message).to be_nil
      end
    end

    context 'when using with_auto_resolve scope' do
      it 'finds accounts with auto_resolve_after set' do
        account.update(auto_resolve_after: 40 * 24 * 60)
        expect(described_class.with_auto_resolve.pluck(:id)).to include(account.id)
      end

      it 'does not find accounts without auto_resolve_after' do
        account.update(auto_resolve_after: nil)
        expect(described_class.with_auto_resolve.pluck(:id)).not_to include(account.id)
      end
    end

    context 'when support_email is set' do
      it 'allows a plain email address' do
        account.support_email = 'support@example.com'
        expect(account).to be_valid
      end

      it 'allows display-name format' do
        account.support_email = 'Support Team <support@example.com>'
        expect(account).to be_valid
      end

      it 'allows blank values' do
        account.support_email = ''
        expect(account).to be_valid
      end

      it 'rejects malformed strings with no email part' do
        account.support_email = 'Smith Smith'
        expect(account).not_to be_valid
        expect(account.errors[:support_email]).to include(I18n.t('errors.account.support_email.invalid'))
      end
    end

    context 'when reporting_timezone is set' do
      it 'allows valid timezone names' do
        account.reporting_timezone = 'America/New_York'

        expect(account).to be_valid
      end

      it 'rejects invalid timezone names' do
        account.reporting_timezone = 'Invalid/Timezone'

        expect(account).not_to be_valid
        expect(account.errors[:reporting_timezone]).to include(I18n.t('errors.account.reporting_timezone.invalid'))
      end
    end
  end

  describe 'ai_agent_settings' do
    let(:account) { create(:account) }

    it 'returns default model when absent' do
      expect(account.ai_agent_model).to eq('deepseek/deepseek-v4-flash')
    end

    it 'returns default limit when absent' do
      expect(account.ai_agent_conversation_limit).to eq(0)
    end

    it 'returns default conversation reuse window when absent' do
      expect(account.ai_agent_conversation_reuse_window_hours).to eq(24)
    end

    it 'is disabled by default' do
      expect(account.ai_agent_enabled?).to be(false)
    end

    it 'allows explicit model to override default' do
      account.update!(ai_agent_model: 'openai/gpt-4o')
      expect(account.reload.ai_agent_model).to eq('openai/gpt-4o')
    end

    it 'allows explicit limit to override default' do
      account.update!(ai_agent_conversation_limit: 100)
      expect(account.reload.ai_agent_conversation_limit).to eq(100)
    end

    it 'allows explicit conversation reuse window to override default' do
      account.update!(ai_agent_conversation_reuse_window_hours: 48)
      expect(account.reload.ai_agent_conversation_reuse_window_hours).to eq(48)
    end

    it 'casts explicit enabled values to boolean' do
      account.update!(ai_agent_enabled: 'true')
      expect(account.reload.ai_agent_enabled?).to be(true)
    end

    it 'returns ai_agent_settings as a hash' do
      expect(account.ai_agent_settings).to eq(
        enabled: false,
        model: 'deepseek/deepseek-v4-flash',
        conversation_limit: 0,
        conversation_reuse_window_hours: 24
      )
    end

    it 'round-trips ai_agent_settings through virtual attribute' do
      account.ai_agent_settings = { enabled: true, model: 'anthropic/claude-3.5-sonnet', conversation_limit: 50, conversation_reuse_window_hours: 48 }
      account.save!
      account.reload

      expect(account.ai_agent_enabled?).to be(true)
      expect(account.ai_agent_model).to eq('anthropic/claude-3.5-sonnet')
      expect(account.ai_agent_conversation_limit).to eq(50)
      expect(account.ai_agent_conversation_reuse_window_hours).to eq(48)
      expect(account.ai_agent_settings).to eq(
        enabled: true,
        model: 'anthropic/claude-3.5-sonnet',
        conversation_limit: 50,
        conversation_reuse_window_hours: 48
      )
    end

    it 'preserves existing settings keys when updating AI settings' do
      account.update!(settings: { auto_resolve_after: 30, auto_resolve_message: 'Hello' })
      account.ai_agent_settings = { model: 'openai/gpt-4o-mini', conversation_limit: 25 }
      account.save!
      account.reload

      expect(account.settings['auto_resolve_after']).to eq(30)
      expect(account.settings['auto_resolve_message']).to eq('Hello')
      expect(account.ai_agent_enabled?).to be(false)
      expect(account.ai_agent_model).to eq('openai/gpt-4o-mini')
      expect(account.ai_agent_conversation_limit).to eq(25)
      expect(account.ai_agent_conversation_reuse_window_hours).to eq(24)
    end
  end

  describe 'voice_agent_runtime_settings' do
    let(:account) { create(:account) }
    let!(:voice_agent) { create(:voice_agent, account: account, architecture: 'realtime', provider: 'gemini', model: nil, voice: 'Charon', language: 'tr') }
    let!(:other_voice_agent) { create(:voice_agent, architecture: 'realtime', provider: 'gemini', voice: 'Puck', language: 'tr') }

    it 'updates runtime settings for account-owned voice agents only' do
      account.voice_agent_runtime_settings = {
        voice_agent.id.to_s => {
          architecture: 'pipeline',
          provider: 'openai',
          model: 'gpt-4o-realtime-preview',
          voice: 'alloy',
          language: 'en',
          prompt: 'ignored'
        },
        other_voice_agent.id.to_s => {
          voice: 'ignored'
        }
      }
      account.save!

      expect(voice_agent.reload).to have_attributes(
        architecture: 'pipeline',
        provider: 'openai',
        model: 'gpt-4o-realtime-preview',
        voice: 'alloy',
        language: 'en'
      )
      expect(voice_agent.prompt).not_to eq('ignored')
      expect(other_voice_agent.reload.voice).to eq('Puck')
    end
  end

  describe 'voice_ai_settings' do
    let(:account) { create(:account) }

    it 'returns defaults when absent' do
      expect(account.voice_ai_settings).to eq(
        enabled: false,
        monthly_minute_limit: 0,
        max_call_duration_minutes: 15,
        concurrent_call_limit: 1
      )
    end

    it 'round-trips voice_ai_settings through virtual attribute' do
      account.voice_ai_settings = {
        enabled: true,
        monthly_minute_limit: 100,
        max_call_duration_minutes: 20,
        concurrent_call_limit: 3
      }
      account.save!
      account.reload

      expect(account.voice_ai_enabled?).to be(true)
      expect(account.voice_ai_monthly_minute_limit).to eq(100)
      expect(account.voice_ai_max_call_duration_minutes).to eq(20)
      expect(account.voice_ai_concurrent_call_limit).to eq(3)
    end

    it 'normalizes invalid numeric values to safe defaults' do
      account.update!(
        voice_ai_monthly_minute_limit: -1,
        voice_ai_max_call_duration_minutes: 0,
        voice_ai_concurrent_call_limit: -2
      )

      expect(account.voice_ai_monthly_minute_limit).to eq(0)
      expect(account.voice_ai_max_call_duration_minutes).to eq(15)
      expect(account.voice_ai_concurrent_call_limit).to eq(0)
    end
  end

  describe '#voice_inbox_setting_for' do
    let(:account) { create(:account) }
    let(:inbox) { create(:channel_api, account: account).inbox }

    it 'returns only account and inbox scoped settings' do
      local_setting = create(:voice_inbox_setting, account: account, inbox: inbox)
      foreign_setting = create(:voice_inbox_setting)

      expect(account.voice_inbox_setting_for(inbox: inbox, id: local_setting.id)).to eq(local_setting)
      expect(account.voice_inbox_setting_for(inbox: inbox, id: foreign_setting.id)).to eq(local_setting)
    end

    it 'does not return another account setting even if a foreign inbox is passed' do
      other_account = create(:account)
      other_inbox = create(:channel_api, account: other_account).inbox
      create(:voice_inbox_setting, account: other_account, inbox: other_inbox)

      expect(account.voice_inbox_setting_for(inbox: other_inbox)).to be_nil
    end
  end

  describe 'captain_preferences' do
    let(:account) { create(:account) }

    describe 'with no saved preferences' do
      before do
        account.update!(captain_models: nil)
      end

      it 'returns defaults from llm.yml' do
        prefs = account.captain_preferences

        expect(prefs[:features].values).to all(be false)

        Llm::Models.feature_keys.each do |feature|
          expect(prefs[:models][feature]).to eq(Llm::Models.default_model_for(feature))
        end
      end

      it 'returns GPT-5.2 for assistant when Captain V2 is enabled' do
        account.enable_features!('captain_integration_v2')

        expect(account.captain_preferences[:models]['assistant']).to eq('gpt-5.2')
        expect(account.reload.captain_models).to be_nil
      end
    end

    describe 'with saved model preferences' do
      it 'returns saved preferences merged with defaults' do
        account.update!(captain_models: { 'editor' => 'gpt-4.1-mini', 'assistant' => 'gpt-5.2' })

        prefs = account.captain_preferences

        expect(prefs[:models]['editor']).to eq('gpt-4.1-mini')
        expect(prefs[:models]['assistant']).to eq('gpt-5.2')
        expect(prefs[:models]['copilot']).to eq(Llm::Models.default_model_for('copilot'))
      end
    end

    describe 'with saved feature preferences' do
      it 'returns saved feature states' do
        account.update!(captain_features: { 'editor' => true, 'assistant' => true })

        prefs = account.captain_preferences

        expect(prefs[:features]['editor']).to be true
        expect(prefs[:features]['assistant']).to be true
        expect(prefs[:features]['copilot']).to be false
      end
    end

    describe 'validation' do
      it 'rejects invalid model for a feature' do
        account.captain_models = { 'label_suggestion' => 'gpt-5.1' }

        expect(account).not_to be_valid
        expect(account.errors[:captain_models].first).to include('not a valid model for label_suggestion')
      end

      it 'accepts valid model for a feature' do
        account.captain_models = { 'editor' => 'gpt-4.1-mini', 'label_suggestion' => 'gpt-4.1-nano' }

        expect(account).to be_valid
      end

      it 'rejects unknown feature keys' do
        account.captain_models = { 'unknown_feature' => 'gpt-4.1' }

        expect(account).not_to be_valid
        expect(account.errors[:captain_models]).to include("'unknown_feature' is not a known feature")
      end

      it 'removes blank model overrides before saving' do
        account.update!(captain_models: { 'editor' => '', 'assistant' => 'gpt-5.2' })

        expect(account.captain_models).to eq('assistant' => 'gpt-5.2')
      end
    end
  end
end
