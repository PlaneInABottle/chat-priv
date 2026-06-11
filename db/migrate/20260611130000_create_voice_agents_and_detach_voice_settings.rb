class CreateVoiceAgentsAndDetachVoiceSettings < ActiveRecord::Migration[7.1]
  def up
    create_table :voice_agents do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false, default: 'Voice Assistant'
      t.boolean :enabled, null: false, default: false
      t.text :greeting
      t.text :prompt, null: false, default: ''
      t.string :architecture, null: false, default: 'realtime'
      t.string :provider, null: false, default: 'gemini'
      t.string :model
      t.string :voice, null: false, default: 'Charon'
      t.string :language, null: false, default: 'tr'
      t.jsonb :tools_config, null: false, default: {}
      t.jsonb :config, null: false, default: {}

      t.timestamps
    end

    add_index :voice_agents, [:account_id, :created_at]
    add_reference :voice_inbox_settings, :voice_agent, foreign_key: true

    say_with_time 'Backfilling voice agents from voice inbox settings' do
      execute <<~SQL.squish
        INSERT INTO voice_agents (
          account_id,
          name,
          enabled,
          greeting,
          prompt,
          architecture,
          provider,
          model,
          voice,
          language,
          tools_config,
          config,
          created_at,
          updated_at
        )
        SELECT
          voice_inbox_settings.account_id,
          'Voice Assistant',
          voice_inbox_settings.ai_agent_id IS NOT NULL,
          voice_inbox_settings.greeting,
          COALESCE(voice_inbox_settings.instructions, ''),
          'realtime',
          'gemini',
          NULL,
          'Charon',
          'tr',
          COALESCE(ai_agents.config -> 'tools', '{"enabled":["human_handoff","end_customer_call"]}'::jsonb),
          jsonb_build_object(
            'migrated_voice_inbox_setting_id', voice_inbox_settings.id,
            'migrated_ai_agent_id', voice_inbox_settings.ai_agent_id
          ),
          NOW(),
          NOW()
        FROM voice_inbox_settings
        LEFT JOIN ai_agents ON ai_agents.id = voice_inbox_settings.ai_agent_id
      SQL

      execute <<~SQL.squish
        UPDATE voice_inbox_settings
        SET voice_agent_id = voice_agents.id
        FROM voice_agents
        WHERE voice_agents.config ->> 'migrated_voice_inbox_setting_id' = voice_inbox_settings.id::text
      SQL
    end

    remove_reference :voice_inbox_settings, :ai_agent, foreign_key: true
    remove_column :voice_inbox_settings, :greeting, :text
    remove_column :voice_inbox_settings, :instructions, :text
  end

  def down
    add_reference :voice_inbox_settings, :ai_agent, foreign_key: true
    add_column :voice_inbox_settings, :greeting, :text
    add_column :voice_inbox_settings, :instructions, :text

    execute <<~SQL.squish
      UPDATE voice_inbox_settings
      SET
        ai_agent_id = ai_agents.id,
        greeting = voice_agents.greeting,
        instructions = voice_agents.prompt
      FROM voice_agents
      LEFT JOIN ai_agents ON ai_agents.id = NULLIF(voice_agents.config ->> 'migrated_ai_agent_id', '')::bigint
      WHERE voice_agents.id = voice_inbox_settings.voice_agent_id
    SQL

    remove_reference :voice_inbox_settings, :voice_agent, foreign_key: true
    drop_table :voice_agents
  end
end
