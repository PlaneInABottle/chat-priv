# frozen_string_literal: true

class AiAgents::ReplyPolicy
  # Escape hatch (single documented override point): flip to false via a future ENV
  # check ONLY if an emergency stop is ever required; do not add flag checks elsewhere.
  HANDOFF_COMPLETED_KEY = 'ai_handoff_completed'

  class << self
    def can_reply?(conversation)
      conversation.pending? && !handoff_completed?(conversation)
    end

    def handoff_completed?(conversation)
      attrs = conversation.additional_attributes
      attrs.is_a?(Hash) && attrs[HANDOFF_COMPLETED_KEY] == true
    end
  end
end
