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
#  current_release_id        :bigint
#
# Indexes
#
#  index_ai_agents_on_account_id          (account_id)
#  index_ai_agents_on_agent_bot_id        (agent_bot_id) UNIQUE
#  index_ai_agents_on_current_release_id  (current_release_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (agent_bot_id => agent_bots.id) ON DELETE => nullify
#  fk_rails_...  (current_release_id => ai_agent_releases.id) ON DELETE => nullify
#
class AiAgent < ApplicationRecord
  belongs_to :account
  belongs_to :agent_bot, optional: true
  belongs_to :current_release, class_name: 'AiAgentRelease', optional: true
  has_many :releases, class_name: 'AiAgentRelease', dependent: :destroy
  has_many :llm_calls, class_name: 'AiAgentLlmCall', dependent: :destroy
  has_many :tool_executions, class_name: 'AiAgentToolExecution', dependent: :destroy
  has_many :test_conversations, class_name: 'AiAgentTestConversation', dependent: :destroy
  has_many :evaluation_cases, class_name: 'AiAgentEvaluationCase', dependent: :destroy
  has_many :evaluation_runs, class_name: 'AiAgentEvaluationRun', dependent: :destroy
  has_many :learning_suggestions, class_name: 'AiAgentLearningSuggestion', dependent: :destroy
  has_many :website_imports, class_name: 'AiAgentWebsiteImport', dependent: :destroy
  has_many :usage_events, class_name: 'AiAgentUsageEvent', dependent: :destroy
  has_many :knowledge_source_assignments, as: :assistant, class_name: 'AiKnowledgeSourceAssignment', dependent: :destroy
  has_many :knowledge_sources, through: :knowledge_source_assignments, source: :ai_knowledge_source

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

  def publish!(created_by: nil)
    with_lock do
      raise ActiveRecord::RecordInvalid, self unless readiness[:can_publish]

      snapshot = AiAgents::ReleaseSnapshot.for(self)
      fingerprint = AiAgents::ReleaseSnapshot.fingerprint(snapshot)
      if current_release&.fingerprint == fingerprint
        update!(enabled: true)
      else
        release = create_release!(snapshot: snapshot, fingerprint: fingerprint, source: 'publish', created_by: created_by)
        activate_release!(release)
      end
    end
  end

  def rollback_to!(release, created_by: nil)
    raise ActiveRecord::RecordNotFound unless release&.ai_agent_id == id

    with_lock do
      restored = create_release!(
        snapshot: release.snapshot,
        fingerprint: release.fingerprint,
        source: 'rollback',
        created_by: created_by
      )
      AiKnowledgeSources::ReleaseAssignmentRestore.new(assistant: self, snapshot: release.snapshot).perform
      activate_release!(restored, restore_draft: true)
      restored
    end
  end

  def pause!
    update!(enabled: false)
  end

  def mark_test_succeeded!(prompt: self.prompt, config: self.config, tested_fingerprint: nil)
    # Test telemetry must remain writable for agents carrying legacy config.
    # rubocop:disable Rails/SkipsModelValidations
    update_columns(
      last_tested_at: Time.current,
      last_tested_prompt_digest: tested_fingerprint || draft_fingerprint(prompt: prompt, config: config),
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

  def draft_fingerprint(prompt: self.prompt, config: self.config)
    release_digest(prompt, config)
  end

  def published_release?
    current_release.present? || published_revision.to_i.positive?
  end

  def draft_changes?
    return false unless published_release?

    draft_fingerprint != current_release&.fingerprint
  end

  def live_prompt
    return current_release.prompt if current_release
    return published_prompt.to_s if published_revision.to_i.positive?

    prompt.to_s
  end

  def live_config
    return current_release.config if current_release
    return published_config.to_h if published_revision.to_i.positive?

    config.to_h
  end

  private

  def create_release!(snapshot:, fingerprint:, source:, created_by:)
    releases.create!(
      account: account,
      created_by: created_by,
      revision: next_release_revision,
      source: source,
      fingerprint: fingerprint,
      snapshot: snapshot
    )
  end

  def activate_release!(release, restore_draft: false)
    attributes = {
      enabled: true,
      published_at: Time.current,
      published_prompt: release.prompt,
      published_config: release.config,
      published_revision: release.revision,
      current_release: release
    }
    attributes.merge!(restored_draft_attributes(release)) if restore_draft
    update!(attributes)
  end

  def restored_draft_attributes(release)
    {
      prompt: release.prompt,
      config: release.config,
      last_tested_at: Time.current,
      last_tested_prompt_digest: release.fingerprint
    }
  end

  def next_release_revision
    [releases.maximum(:revision).to_i, published_revision.to_i].max + 1
  end

  def release_digest(prompt_value, config_value)
    payload = {
      'prompt' => prompt_value.to_s,
      'config' => runtime_config(config_value),
      'knowledge_sources' => AiKnowledgeSources::Snapshot.for(self)
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
