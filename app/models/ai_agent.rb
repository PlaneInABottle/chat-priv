# == Schema Information
#
# Table name: ai_agents
#
#  id           :bigint           not null, primary key
#  account_id   :bigint           not null
#  agent_bot_id :bigint
#  prompt       :text             default("")
#  enabled      :boolean          default(FALSE)
#  config       :jsonb            default({})
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_ai_agents_on_account_id    (account_id) UNIQUE
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
  has_many :test_conversations, class_name: 'AiAgentTestConversation', dependent: :destroy

  validates :name, presence: true
  validates :prompt, length: { maximum: 50_000 }
  validate :inbox_ids_conflict, if: -> { inbox_ids.present? }
  validate :tools_config_must_be_valid

  attr_accessor :inbox_ids

  after_create :create_linked_agent_bot
  before_destroy :destroy_linked_agent_bot

  private

  def inbox_ids_conflict
    target_ids = Array(inbox_ids).map(&:to_i).select(&:positive?).uniq
    return if target_ids.empty?

    conflicts = AgentBotInbox.where.not(agent_bot_id: agent_bot_id)
                             .where(inbox_id: target_ids)
                             .exists?

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
