class BackfillAiAgentGlobalInstructions < ActiveRecord::Migration[7.0]
  DEFAULT_PROMPT = <<~PROMPT
    You are a helpful AI assistant for a customer support team.
    Follow these instructions carefully.
    Be concise, professional, and helpful. If you cannot answer something,
    politely say so and suggest handing off to a human agent.
  PROMPT

  def up
    config = InstallationConfig.where(name: 'AI_AGENT_GLOBAL_INSTRUCTIONS').first_or_initialize
    config.value = DEFAULT_PROMPT if config.value.blank?
    config.locked = false if config.locked.nil?
    config.save!
  end

  def down
    config = InstallationConfig.find_by(name: 'AI_AGENT_GLOBAL_INSTRUCTIONS')
    return unless config&.value == DEFAULT_PROMPT

    config.update!(value: nil)
  end
end
