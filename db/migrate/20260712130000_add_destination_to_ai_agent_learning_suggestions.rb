class AddDestinationToAiAgentLearningSuggestions < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_learning_suggestions, :destination, :string, default: 'instructions', null: false
    add_column :ai_agent_learning_suggestions, :source_name, :string
    add_reference :ai_agent_learning_suggestions,
                  :ai_knowledge_source,
                  foreign_key: { on_delete: :nullify },
                  index: true

    add_check_constraint :ai_agent_learning_suggestions,
                         "destination IN ('instructions', 'knowledge')",
                         name: 'ai_learning_suggestions_destination_check'
  end
end
