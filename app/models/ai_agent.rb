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
  has_many :test_conversations, class_name: 'AiAgentTestConversation', dependent: :destroy_async

  validates :account_id, uniqueness: true
  validates :prompt, length: { maximum: 50_000 }

  after_create :create_linked_agent_bot

  private

  def create_linked_agent_bot
    bot = account.agent_bots.create!(name: 'AI Asistan', bot_type: :ai, outgoing_url: nil)
    # rubocop:disable Rails/SkipsModelValidations — intentional: skip validations to avoid recursive callback
    update_column(:agent_bot_id, bot.id)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
