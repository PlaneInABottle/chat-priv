# == Schema Information
#
# Table name: accounts
#
#  id                    :integer          not null, primary key
#  auto_resolve_duration :integer
#  custom_attributes     :jsonb
#  domain                :string(100)
#  feature_flags         :bigint           default(0), not null
#  internal_attributes   :jsonb            not null
#  limits                :jsonb
#  locale                :integer          default("en")
#  name                  :string           not null
#  settings              :jsonb
#  status                :integer          default("active")
#  support_email         :string(100)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_accounts_on_status  (status)
#

class Account < ApplicationRecord
  # used for single column multi flags
  include FlagShihTzu
  include Reportable
  include Featurable
  include CacheKeys
  include CaptainFeaturable
  include AccountEmailRateLimitable
  include AccountSettingsSchema

  DEFAULT_AI_AGENT_MODEL = 'deepseek/deepseek-v4-flash-0731'.freeze
  AI_AGENT_MODELS = [
    DEFAULT_AI_AGENT_MODEL,
    'openai/gpt-4o',
    'openai/gpt-4o-mini',
    'anthropic/claude-3.5-sonnet',
    'anthropic/claude-3.5-haiku',
    'google/gemini-2.0-flash-001',
    'meta-llama/llama-3.3-70b-instruct'
  ].freeze
  DEFAULT_AI_IMPROVEMENT_MONTHLY_CREDIT_LIMIT = 1000

  DEFAULT_QUERY_SETTING = {
    flag_query_mode: :bit_operator,
    check_for_column: false
  }.freeze

  validates :name, presence: true
  # `domain` is the inbound email domain used to construct reply addresses
  # (see `inbound_email_domain`). Do not repurpose it for a website or any
  # non-mail-related domain.
  validates :domain, length: { maximum: 100 }
  validates_with JsonSchemaValidator,
                 schema: SETTINGS_PARAMS_SCHEMA,
                 attribute_resolver: ->(record) { record.settings }
  validate :validate_reporting_timezone
  validate :validate_support_email_format, if: :will_save_change_to_support_email?

  store_accessor :settings, :auto_resolve_after, :auto_resolve_message, :auto_resolve_ignore_waiting

  store_accessor :settings, :audio_transcriptions, :auto_resolve_label
  store_accessor :settings, :captain_models, :captain_features
  store_accessor :settings, :reporting_timezone
  store_accessor :settings, :keep_pending_on_bot_failure
  store_accessor :settings, :captain_auto_resolve_mode
  store_accessor :settings, :ai_agent_enabled, :ai_agent_model, :ai_agent_conversation_limit, :ai_agent_conversation_reuse_window_hours,
                 :ai_agent_data_retention_days
  store_accessor :settings, :ai_improvement_monthly_credit_limit
  store_accessor :settings, :voice_ai_enabled, :voice_ai_monthly_minute_limit, :voice_ai_max_call_duration_minutes, :voice_ai_concurrent_call_limit,
                 :voice_ai_data_retention_days

  attr_reader :voice_agent_runtime_settings

  include AccountCaptainAutoResolve

  has_many :account_users, dependent: :destroy_async
  has_many :agent_bot_inboxes, dependent: :destroy_async
  has_many :agent_bots, dependent: :destroy_async
  has_many :ai_agents, dependent: :destroy
  has_many :voice_agents, dependent: :destroy
  has_many :ai_knowledge_sources, dependent: :destroy
  has_many :ai_knowledge_source_assignments, dependent: :destroy
  has_many :ai_agent_llm_calls, dependent: :destroy
  has_many :ai_agent_tool_executions, dependent: :destroy
  has_many :ai_agent_usage_events, dependent: :destroy
  has_many :ai_improvement_usage_events, dependent: :destroy
  has_many :ai_agent_evaluation_cases, dependent: :destroy
  has_many :ai_agent_evaluation_runs, dependent: :destroy
  has_many :ai_agent_learning_suggestions, dependent: :destroy
  has_many :ai_agent_website_imports, dependent: :destroy
  has_many :api_channels, dependent: :destroy_async, class_name: '::Channel::Api'
  has_many :articles, dependent: :destroy_async, class_name: '::Article'
  has_many :assignment_policies, dependent: :destroy_async
  has_many :automation_rules, dependent: :destroy_async
  has_many :macros, dependent: :destroy_async
  has_many :campaigns, dependent: :destroy_async
  has_many :calls, dependent: :destroy_async
  has_many :call_transcript_segments, dependent: :destroy_async
  has_many :voice_recordings, dependent: :destroy
  has_many :voice_provider_connections, dependent: :destroy
  has_many :voice_numbers, dependent: :destroy
  has_many :voice_tool_events, dependent: :destroy
  has_many :canned_responses, dependent: :destroy_async
  has_many :categories, dependent: :destroy_async, class_name: '::Category'
  has_many :contacts, dependent: :destroy_async
  has_many :conversations, dependent: :destroy_async
  has_many :csat_survey_responses, dependent: :destroy_async
  has_many :custom_attribute_definitions, dependent: :destroy_async
  has_many :custom_filters, dependent: :destroy_async
  has_many :dashboard_apps, dependent: :destroy_async
  has_many :data_imports, dependent: :destroy_async
  has_many :email_channels, dependent: :destroy_async, class_name: '::Channel::Email'
  has_many :facebook_pages, dependent: :destroy_async, class_name: '::Channel::FacebookPage'
  has_many :instagram_channels, dependent: :destroy_async, class_name: '::Channel::Instagram'
  has_many :tiktok_channels, dependent: :destroy_async, class_name: '::Channel::Tiktok'
  has_many :hooks, dependent: :destroy_async, class_name: 'Integrations::Hook'
  has_many :ikas_catalog_snapshots, dependent: :destroy_async
  has_many :inboxes, dependent: :destroy_async
  has_many :labels, dependent: :destroy_async
  has_many :line_channels, dependent: :destroy_async, class_name: '::Channel::Line'
  has_many :mentions, dependent: :destroy_async
  has_many :messages, dependent: :destroy_async
  has_many :notes, dependent: :destroy_async
  has_many :notification_settings, dependent: :destroy_async
  has_many :notifications, dependent: :destroy_async
  has_many :portals, dependent: :destroy_async, class_name: '::Portal'
  has_many :sms_channels, dependent: :destroy_async, class_name: '::Channel::Sms'
  has_many :teams, dependent: :destroy_async
  has_many :telegram_channels, dependent: :destroy_async, class_name: '::Channel::Telegram'
  has_many :twilio_sms, dependent: :destroy_async, class_name: '::Channel::TwilioSms'
  has_many :twitter_profiles, dependent: :destroy_async, class_name: '::Channel::TwitterProfile'
  has_many :users, through: :account_users
  has_many :web_widgets, dependent: :destroy_async, class_name: '::Channel::WebWidget'
  has_many :webhooks, dependent: :destroy_async
  has_many :whatsapp_channels, dependent: :destroy_async, class_name: '::Channel::Whatsapp'
  has_many :voice_inbox_settings, dependent: :destroy_async
  has_many :working_hours, dependent: :destroy_async

  has_one_attached :contacts_export

  enum :locale, LANGUAGES_CONFIG.map { |key, val| [val[:iso_639_1_code], key] }.to_h, prefix: true
  enum :status, { active: 0, suspended: 1 }

  scope :with_auto_resolve, -> { where("(settings ->> 'auto_resolve_after')::int IS NOT NULL") }

  before_validation :validate_limit_keys
  after_create_commit :notify_creation
  after_save :apply_voice_agent_runtime_settings, if: -> { @voice_agent_runtime_settings.present? }
  after_update_commit :clear_unread_conversation_counts_cache, if: :saved_change_to_feature_conversation_unread_counts?
  after_update_commit :finalize_active_voice_ai_calls, if: :voice_ai_access_disabled_after_update?
  after_destroy :remove_account_sequences

  def agents
    users.where(account_users: { role: :agent })
  end

  def administrators
    users.where(account_users: { role: :administrator })
  end

  def all_conversation_tags
    # returns array of tags
    conversation_ids = conversations.pluck(:id)
    ActsAsTaggableOn::Tagging.includes(:tag)
                             .where(context: 'labels',
                                    taggable_type: 'Conversation',
                                    taggable_id: conversation_ids)
                             .map { |tagging| tagging.tag.name }
  end

  def webhook_data
    {
      id: id,
      name: name
    }
  end

  def inbound_email_domain
    domain.presence || GlobalConfig.get('MAILER_INBOUND_EMAIL_DOMAIN')['MAILER_INBOUND_EMAIL_DOMAIN'] || ENV.fetch('MAILER_INBOUND_EMAIL_DOMAIN',
                                                                                                                   false)
  end

  def support_email
    super.presence || ENV.fetch('MAILER_SENDER_EMAIL') { GlobalConfig.get('MAILER_SUPPORT_EMAIL')['MAILER_SUPPORT_EMAIL'] }
  end

  def ai_agent_settings
    {
      enabled: ai_agent_enabled?,
      model: ai_agent_model,
      conversation_limit: ai_agent_conversation_limit,
      conversation_reuse_window_hours: ai_agent_conversation_reuse_window_hours,
      data_retention_days: ai_agent_data_retention_days
    }
  end

  def ai_agent_settings=(value)
    return unless value.is_a?(Hash)

    settings = value.with_indifferent_access
    self.ai_agent_enabled = settings[:enabled] if settings.key?(:enabled)
    self.ai_agent_model = settings[:model] if settings.key?(:model)
    self.ai_agent_conversation_limit = settings[:conversation_limit] if settings.key?(:conversation_limit)
    if settings.key?(:conversation_reuse_window_hours)
      self.ai_agent_conversation_reuse_window_hours = settings[:conversation_reuse_window_hours]
    end
    if settings.key?(:data_retention_days)
      self.ai_agent_data_retention_days = AiDataRetention::Policy.normalize_days(settings[:data_retention_days])
    end
  end

  def ai_agent_enabled?
    ActiveModel::Type::Boolean.new.cast(ai_agent_enabled) == true
  end

  def ai_agent_model
    super.presence || DEFAULT_AI_AGENT_MODEL
  end

  def ai_agent_conversation_limit
    (super || 0).to_i
  end

  def ai_agent_conversation_reuse_window_hours
    value = (super || 24).to_i
    value.positive? ? value : 24
  end

  def ai_agent_data_retention_days
    AiDataRetention::Policy.normalize_days(super)
  end

  def ai_improvement_settings
    { monthly_credit_limit: ai_improvement_monthly_credit_limit }
  end

  def ai_improvement_settings=(value)
    return unless value.is_a?(Hash)

    settings = value.with_indifferent_access
    return unless settings.key?(:monthly_credit_limit)

    parsed = Integer(settings[:monthly_credit_limit], exception: false)
    valid_limit = parsed && !parsed.negative?
    self.ai_improvement_monthly_credit_limit = valid_limit ? parsed : DEFAULT_AI_IMPROVEMENT_MONTHLY_CREDIT_LIMIT
  end

  def ai_improvement_monthly_credit_limit
    value = super
    return DEFAULT_AI_IMPROVEMENT_MONTHLY_CREDIT_LIMIT if value.nil?

    parsed = Integer(value, exception: false)
    return DEFAULT_AI_IMPROVEMENT_MONTHLY_CREDIT_LIMIT if parsed.nil? || parsed.negative?

    parsed
  end

  def voice_ai_settings
    {
      enabled: voice_ai_enabled?,
      monthly_minute_limit: voice_ai_monthly_minute_limit,
      max_call_duration_minutes: voice_ai_max_call_duration_minutes,
      concurrent_call_limit: voice_ai_concurrent_call_limit,
      data_retention_days: voice_ai_data_retention_days
    }
  end

  def voice_ai_settings=(value)
    return unless value.is_a?(Hash)

    settings = value.with_indifferent_access
    self.voice_ai_enabled = settings[:enabled] if settings.key?(:enabled)
    self.voice_ai_monthly_minute_limit = settings[:monthly_minute_limit] if settings.key?(:monthly_minute_limit)
    self.voice_ai_max_call_duration_minutes = settings[:max_call_duration_minutes] if settings.key?(:max_call_duration_minutes)
    self.voice_ai_concurrent_call_limit = settings[:concurrent_call_limit] if settings.key?(:concurrent_call_limit)
    if settings.key?(:data_retention_days)
      self.voice_ai_data_retention_days = AiDataRetention::Policy.normalize_days(settings[:data_retention_days])
    end
  end

  def voice_ai_enabled?
    ActiveModel::Type::Boolean.new.cast(voice_ai_enabled) == true
  end

  def voice_ai_monthly_minute_limit
    non_negative_integer(super)
  end

  def voice_ai_max_call_duration_minutes
    positive_integer(super, 15)
  end

  def voice_ai_concurrent_call_limit
    non_negative_integer(super.presence || 1)
  end

  def voice_ai_data_retention_days
    AiDataRetention::Policy.normalize_days(super)
  end

  def voice_inbox_setting_for(inbox:, id: nil)
    scoped_settings = voice_inbox_settings.where(account_id: self.id, inbox: inbox)
    return scoped_settings.find_by(id: id) || scoped_settings.first if id.present?

    scoped_settings.first
  end

  def voice_agent_runtime_settings=(value)
    @voice_agent_runtime_settings = value if value.is_a?(Hash)
  end

  def usage_limits
    {
      agents: ChatwootApp.max_limit.to_i,
      inboxes: ChatwootApp.max_limit.to_i
    }
  end

  def locale_english_name
    # the locale can also be something like pt_BR, en_US, fr_FR, etc.
    # the format is `<locale_code>_<country_code>`
    # we need to extract the language code from the locale
    account_locale = locale&.split('_')&.first
    ISO_639.find(account_locale)&.english_name&.downcase || 'english'
  end

  def onboarding_step
    step = custom_attributes['onboarding_step']
    return nil if step.blank?

    enrichment_key = format(Redis::Alfred::ACCOUNT_ONBOARDING_ENRICHMENT, account_id: id)
    Redis::Alfred.exists?(enrichment_key) ? 'enrichment' : step
  end

  def reset_cache_keys
    super
    clear_unread_conversation_counts_cache
  end

  private

  def notify_creation
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CREATED, Time.zone.now, account: self)
  end

  def apply_voice_agent_runtime_settings
    @voice_agent_runtime_settings.each do |voice_agent_id, settings|
      next unless settings.is_a?(Hash)

      voice_agent = voice_agents.find_by(id: voice_agent_id)
      next unless voice_agent

      voice_agent.update!(settings.with_indifferent_access.slice(:architecture, :provider, :model, :voice, :language))
    end
  ensure
    @voice_agent_runtime_settings = nil
  end

  def clear_unread_conversation_counts_cache
    ::Conversations::UnreadCounts::Store.clear_account!(id)
  end

  def voice_ai_access_disabled_after_update?
    return false unless saved_change_to_settings?

    previous_settings, current_settings = saved_change_to_settings
    previous_enabled = ActiveModel::Type::Boolean.new.cast((previous_settings || {})['voice_ai_enabled'])
    current_enabled = ActiveModel::Type::Boolean.new.cast((current_settings || {})['voice_ai_enabled'])

    previous_enabled && !current_enabled
  end

  def finalize_active_voice_ai_calls
    Voice::AccountCallFinalizerJob.perform_later(self)
  end

  trigger.after(:insert).for_each(:row) do
    "execute format('create sequence IF NOT EXISTS conv_dpid_seq_%s', NEW.id);"
  end

  trigger.name('camp_dpid_before_insert').after(:insert).for_each(:row) do
    "execute format('create sequence IF NOT EXISTS camp_dpid_seq_%s', NEW.id);"
  end

  def validate_limit_keys
    # method overridden in enterprise module
  end

  def non_negative_integer(value)
    [value.to_i, 0].max
  end

  def positive_integer(value, fallback)
    parsed_value = value.to_i
    parsed_value.positive? ? parsed_value : fallback
  end

  def validate_reporting_timezone
    return if reporting_timezone.blank? || ActiveSupport::TimeZone[reporting_timezone].present?

    errors.add(:reporting_timezone, I18n.t('errors.account.reporting_timezone.invalid'))
  end

  def validate_support_email_format
    value = attributes['support_email']
    return if value.blank?

    parsed = Mail::Address.new(value).address
    errors.add(:support_email, I18n.t('errors.account.support_email.invalid')) if parsed.blank?
  rescue Mail::Field::ParseError, Mail::Field::IncompleteParseError
    errors.add(:support_email, I18n.t('errors.account.support_email.invalid'))
  end

  def remove_account_sequences
    ActiveRecord::Base.connection.exec_query("drop sequence IF EXISTS camp_dpid_seq_#{id}")
    ActiveRecord::Base.connection.exec_query("drop sequence IF EXISTS conv_dpid_seq_#{id}")
  end
end

Account.prepend_mod_with('Account')
Account.prepend_mod_with('Account::PlanUsageAndLimits')
Account.include_mod_with('Concerns::Account')
Account.include_mod_with('Audit::Account')
