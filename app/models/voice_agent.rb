# == Schema Information
#
# Table name: voice_agents
#
#  id                            :bigint           not null, primary key
#  architecture                  :string           default("realtime"), not null
#  config                        :jsonb            not null
#  enabled                       :boolean          default(FALSE), not null
#  greeting                      :text
#  language                      :string           default("tr"), not null
#  last_tested_at                :datetime
#  last_tested_draft_fingerprint :string
#  model                         :string
#  name                          :string           default("Voice Assistant"), not null
#  prompt                        :text             default(""), not null
#  provider                      :string           default("gemini"), not null
#  published_at                  :datetime
#  tools_config                  :jsonb            not null
#  voice                         :string           default("Charon"), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id                    :bigint           not null
#  current_release_id            :bigint
#
# Indexes
#
#  index_voice_agents_on_account_id                 (account_id)
#  index_voice_agents_on_account_id_and_created_at  (account_id,created_at)
#  index_voice_agents_on_current_release_id         (current_release_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (current_release_id => voice_agent_releases.id) ON DELETE => nullify
#
class VoiceAgent < ApplicationRecord
  ARCHITECTURES = %w[realtime pipeline].freeze
  PROVIDERS = %w[gemini openai].freeze
  OPENAI_REALTIME_MODELS = %w[gpt-realtime-2.1].freeze
  OPENAI_REALTIME_VOICES = %w[alloy ash ballad coral echo sage shimmer verse marin cedar].freeze

  belongs_to :account
  belongs_to :current_release, class_name: 'VoiceAgentRelease', optional: true
  has_many :releases, class_name: 'VoiceAgentRelease', dependent: :destroy
  has_many :voice_inbox_settings, dependent: :nullify
  has_many :knowledge_source_assignments,
           as: :assistant,
           class_name: 'AiKnowledgeSourceAssignment',
           dependent: :destroy
  has_many :knowledge_sources, through: :knowledge_source_assignments, source: :ai_knowledge_source

  scope :enabled, -> { where(enabled: true) }

  validates :name, presence: true
  validates :architecture, presence: true, inclusion: { in: ARCHITECTURES }
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :language, presence: true
  validates :voice, presence: true
  validates :greeting, length: { maximum: 20_000 }
  validates :prompt, length: { maximum: 50_000 }
  validate :tools_config_must_be_valid
  validate :openai_realtime_runtime_must_be_valid

  before_validation :set_defaults

  def lifecycle_status
    return 'active' if enabled?
    return 'paused' if published_at.present?

    'draft'
  end

  def readiness
    VoiceAgents::Readiness.new(self).payload
  end

  def publish!(created_by: nil, activate: true)
    with_lock do
      raise ActiveRecord::RecordInvalid, self unless readiness[:can_publish]

      snapshot = VoiceAgents::ReleaseSnapshot.for(self)
      fingerprint = AssistantReleases::Snapshot.fingerprint(snapshot)
      if current_release&.fingerprint == fingerprint
        update!(enabled: activate, published_at: published_at || Time.current)
      else
        release = releases.create!(
          account: account,
          created_by: created_by,
          revision: next_release_revision,
          source: 'publish',
          fingerprint: fingerprint,
          snapshot: snapshot
        )
        update!(enabled: activate, published_at: Time.current, current_release: release)
      end
    end
  end

  def rollback_to!(release, created_by: nil)
    raise ActiveRecord::RecordNotFound unless release&.voice_agent_id == id

    with_lock do
      restored = releases.create!(
        account: account,
        created_by: created_by,
        revision: next_release_revision,
        source: 'rollback',
        fingerprint: release.fingerprint,
        snapshot: release.snapshot
      )
      restore_release_draft(restored)
      self.published_at = Time.current
      self.current_release = restored
      self.last_tested_at = Time.current
      self.last_tested_draft_fingerprint = restored.fingerprint
      save!
      restored
    end
  end

  def pause!
    update!(enabled: false)
  end

  def activate!
    unless current_release
      errors.add(:base, 'Publish the assistant before activation.')
      raise ActiveRecord::RecordInvalid, self
    end

    update!(enabled: true, published_at: published_at || Time.current)
  end

  def mark_test_succeeded!(tested_fingerprint: draft_fingerprint)
    update!(last_tested_at: Time.current, last_tested_draft_fingerprint: tested_fingerprint)
  end

  def draft_fingerprint
    AssistantReleases::Snapshot.fingerprint(VoiceAgents::ReleaseSnapshot.for(self))
  end

  def draft_tested?
    last_tested_at.present? && last_tested_draft_fingerprint == draft_fingerprint
  end

  def draft_changes?
    current_release.present? && current_release.fingerprint != draft_fingerprint
  end

  def published_revision
    current_release&.revision.to_i
  end

  def live_value(key)
    return current_release.value(key) if current_release

    public_send(key)
  end

  private

  def restore_release_draft(release)
    assign_attributes(release.snapshot.slice(*VoiceAgents::ReleaseSnapshot::ATTRIBUTES))
    AiKnowledgeSources::ReleaseAssignmentRestore.new(assistant: self, snapshot: release.snapshot).perform
  end

  def next_release_revision
    releases.maximum(:revision).to_i + 1
  end

  def set_defaults
    self.tools_config = {} unless tools_config.is_a?(Hash)
    self.config = {} unless config.is_a?(Hash)
  end

  def tools_config_must_be_valid
    parsed_config = VoiceAgents::Config.new(tools_config)
    return if parsed_config.valid?

    parsed_config.errors.each { |message| errors.add(:tools_config, message) }
  end

  def openai_realtime_runtime_must_be_valid
    return unless architecture == 'realtime' && provider == 'openai'

    errors.add(:model, 'must be a supported OpenAI realtime model') unless OPENAI_REALTIME_MODELS.include?(model)
    errors.add(:voice, 'must be a supported OpenAI realtime voice') unless OPENAI_REALTIME_VOICES.include?(voice)
  end
end
