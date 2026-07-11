# == Schema Information
#
# Table name: ai_agents
#
#  id                        :bigint           not null, primary key
#  config                    :jsonb
#  enabled                   :boolean          default(FALSE), not null
#  last_tested_at            :datetime
#  last_tested_prompt_digest :string
#  name                      :string           default("AI Asistan"), not null
#  prompt                    :text             default("")
#  published_at              :datetime
#  published_config          :jsonb            not null
#  published_prompt          :text
#  published_revision        :integer          default(0), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#  agent_bot_id              :bigint
#
# Indexes
#
#  index_ai_agents_on_account_id    (account_id)
#  index_ai_agents_on_agent_bot_id  (agent_bot_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (agent_bot_id => agent_bots.id) ON DELETE => nullify
#
class AiAgent < ApplicationRecord
  belongs_to :account
  belongs_to :agent_bot, optional: true
  has_many :llm_calls, class_name: 'AiAgentLlmCall', dependent: :destroy
  has_many :tool_executions, class_name: 'AiAgentToolExecution', dependent: :destroy
  has_many :test_conversations, class_name: 'AiAgentTestConversation', dependent: :destroy
  has_many :evaluation_cases, class_name: 'AiAgentEvaluationCase', dependent: :destroy
  has_many :evaluation_runs, class_name: 'AiAgentEvaluationRun', dependent: :destroy
  has_many :learning_suggestions, class_name: 'AiAgentLearningSuggestion', dependent: :destroy
  has_many :website_imports, class_name: 'AiAgentWebsiteImport', dependent: :destroy
  has_many :usage_events, class_name: 'AiAgentUsageEvent', dependent: :destroy

  validates :name, presence: true
  validates :prompt, length: { maximum: 50_000 }
  validate :inbox_ids_conflict, if: -> { inbox_ids.present? }
  validate :tools_config_must_be_valid

  attr_accessor :inbox_ids

  after_create :create_linked_agent_bot
  before_destroy :destroy_linked_agent_bot

  def lifecycle_status
    return 'active' if enabled?
    return 'paused' if published_at.present?

    'draft'
  end

  def readiness
    AiAgents::Readiness.new(self).payload
  end

  def publish!
    with_lock do
      raise ActiveRecord::RecordInvalid, self unless readiness[:can_publish]

      if published_release? && !draft_changes?
        update!(enabled: true)
      else
        update!(
          enabled: true,
          published_at: Time.current,
          published_prompt: prompt,
          published_config: config || {},
          published_revision: published_revision.to_i + 1
        )
      end
    end
  end

  def pause!
    update!(enabled: false)
  end

  def mark_test_succeeded!(prompt: self.prompt, config: self.config)
    # Test telemetry must remain writable for agents carrying legacy config.
    # rubocop:disable Rails/SkipsModelValidations
    update_columns(
      last_tested_at: Time.current,
      last_tested_prompt_digest: release_digest(prompt, config),
      updated_at: Time.current
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  def prompt_tested?
    draft_tested?
  end

  def draft_tested?
    last_tested_at.present? && last_tested_prompt_digest == release_digest(prompt, config)
  end

  def draft_fingerprint
    release_digest(prompt, config)
  end

  def published_release?
    published_revision.to_i.positive?
  end

  def draft_changes?
    return false unless published_release?

    release_digest(prompt, config) != release_digest(live_prompt, live_config)
  end

  def live_prompt
    published_release? ? published_prompt.to_s : prompt.to_s
  end

  def live_config
    published_release? ? published_config.to_h : config.to_h
  end

  private

  def release_digest(prompt_value, config_value)
    payload = {
      'prompt' => prompt_value.to_s,
      'config' => runtime_config(config_value)
    }
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(payload)))
  end

  def runtime_config(value)
    value.is_a?(Hash) ? value.deep_stringify_keys.except('instructions') : {}
  end

  def canonicalize(value)
    case value
    when Hash
      value.keys.sort.index_with { |key| canonicalize(value[key]) }
    when Array
      value.map { |item| canonicalize(item) }
    else
      value
    end
  end

  def inbox_ids_conflict
    target_ids = Array(inbox_ids).map(&:to_i).select(&:positive?).uniq
    return if target_ids.empty?

    conflicts = AgentBotInbox.where.not(agent_bot_id: agent_bot_id)
                             .exists?(inbox_id: target_ids)

    errors.add(:inbox_ids, 'already assigned to another agent bot') if conflicts
  end

  def tools_config_must_be_valid
    parsed_config = AiAgents::Config.new(config)
    return if parsed_config.valid?

    parsed_config.errors.each do |message|
      errors.add(:config, message)
    end
  end

  def destroy_linked_agent_bot
    bot = agent_bot
    return unless bot

    bot.agent_bot_inboxes.destroy_all
    bot.destroy!
  end

  def create_linked_agent_bot
    bot = account.agent_bots.create!(name: name, bot_type: :ai, outgoing_url: nil)
    # rubocop:disable Rails/SkipsModelValidations — intentional: skip validations to avoid recursive callback
    update_column(:agent_bot_id, bot.id)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
