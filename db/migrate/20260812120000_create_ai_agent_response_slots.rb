# frozen_string_literal: true

# Expand-only: adds the per-(event, trigger message) response slot reservation table
# and the warning-sent flag on usage events. Safe for zero-downtime deployment; old
# application versions ignore the new table and column.
class CreateAiAgentResponseSlots < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_agent_response_slots do |t|
      t.references :ai_agent_usage_event, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :trigger_message, null: false, index: false, foreign_key: { to_table: :messages, on_delete: :cascade }
      t.integer :status, null: false, default: 0
      t.timestamps
    end

    add_index :ai_agent_response_slots, %i[ai_agent_usage_event_id trigger_message_id],
              unique: true, name: 'idx_ai_agent_response_slots_on_event_trigger'
    add_index :ai_agent_response_slots, %i[ai_agent_usage_event_id status],
              name: 'idx_ai_agent_response_slots_on_event_status'
    add_index :ai_agent_response_slots, :trigger_message_id,
              name: 'index_ai_agent_response_slots_on_trigger_message_id'

    add_column :ai_agent_usage_events, :response_limit_warning_sent, :boolean, null: false, default: false
  end
end
