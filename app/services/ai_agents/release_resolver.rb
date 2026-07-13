# frozen_string_literal: true

class AiAgents::ReleaseResolver
  def self.for(conversation:, ai_agent:)
    pinned = conversation.ai_agent_release
    return pinned if pinned&.ai_agent_id == ai_agent.id

    conversation.class.transaction do
      locked_conversation = conversation.class.lock.find(conversation.id)
      pinned = locked_conversation.ai_agent_release
      if pinned&.ai_agent_id == ai_agent.id
        pinned
      else
        ai_agent.reload.current_release.tap do |release|
          locked_conversation.update!(ai_agent_release: release) if release
        end
      end
    end
  end
end
