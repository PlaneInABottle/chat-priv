# frozen_string_literal: true

class AiAgents::OnboardingCreator
  Result = Data.define(:ai_agent, :website_import)
  CUSTOM_ATTRIBUTE_KEYS = %w[website industry company_size timezone referral_source user_role].freeze

  class ExistingAssistant < StandardError; end

  def initialize(account:, user:, account_attributes:, assistant_attributes:)
    @account = account
    @user = user
    @account_attributes = account_attributes.deep_stringify_keys
    @assistant_attributes = assistant_attributes.deep_stringify_keys
  end

  def perform
    normalize_website!
    ai_agent = create_fallback_agent
    website_import = create_website_import(ai_agent)
    Result.new(ai_agent: ai_agent, website_import: website_import)
  end

  private

  attr_reader :account, :user, :account_attributes, :assistant_attributes

  def normalize_website!
    return if account_attributes['website'].blank?

    account_attributes['website'] = AiAgents::WebsiteCrawler.normalize_url(account_attributes['website'])
  end

  def create_fallback_agent
    account.with_lock do
      existing = onboarding_agent
      next existing if existing
      raise ExistingAssistant, 'This account already has a Text AI assistant.' if account.ai_agents.exists?

      persist_account_answers
      account.ai_agents.create!(draft_builder.agent_attributes)
    end
  end

  def persist_account_answers
    account.locale = account_attributes['locale'] if account_attributes['locale'].present?
    CUSTOM_ATTRIBUTE_KEYS.each do |key|
      account.custom_attributes[key] = account_attributes[key] if account_attributes.key?(key)
    end
    account.custom_attributes['onboarding_step'] = 'ai_assistant'
    account.save!
  end

  def onboarding_agent
    account.ai_agents.where("config -> 'setup_profile' ->> 'source' = ?", 'account_onboarding').order(:id).first
  end

  def draft_builder
    AiAgents::OnboardingDraftBuilder.new(
      account: account,
      answers: account_attributes.merge(assistant_attributes).merge('language' => account_attributes['locale'])
    )
  end

  def create_website_import(ai_agent)
    return if account_attributes['website'].blank?

    AiAgents::WebsiteImportCreator.new(
      ai_agent: ai_agent,
      website_url: account_attributes['website'],
      requested_by: user,
      mode: :initial
    ).perform
  end
end
