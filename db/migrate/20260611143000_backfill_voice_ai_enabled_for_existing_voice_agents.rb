class BackfillVoiceAiEnabledForExistingVoiceAgents < ActiveRecord::Migration[7.1]
  def up
    # Preserve existing active Voice AI accounts before creating default agents for old accounts.
    # Accounts without a previous Voice AI setup get a default agent, but stay disabled until Super Admin enables them.
    execute <<~SQL.squish
      UPDATE accounts
      SET settings = COALESCE(settings, '{}'::jsonb) || jsonb_build_object('voice_ai_enabled', true)
      WHERE EXISTS (
        SELECT 1
        FROM voice_agents
        WHERE voice_agents.account_id = accounts.id
          AND voice_agents.enabled = TRUE
          AND COALESCE(voice_agents.config ->> 'backfilled_default_agent', 'false') != 'true'
      )
        AND NOT (COALESCE(settings, '{}'::jsonb) ? 'voice_ai_enabled')
    SQL

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
        accounts.id,
        'Voice Assistant',
        TRUE,
        'Merhaba, size nasil yardimci olabilirim?',
        'Yalnizca dogal Istanbul Turkcesiyle konus. Kisa, net ve sakin musteri destek cevaplari ver.',
        'realtime',
        'gemini',
        NULL,
        'Charon',
        'tr',
        jsonb_build_object(
          'enabled', jsonb_build_array('human_handoff', 'end_customer_call'),
          'human_handoff', jsonb_build_object('allowed_labels', jsonb_build_array()),
          'ikas_lookup_order', jsonb_build_object('enabled', false),
          'ikas_catalog_search', jsonb_build_object(),
          'end_customer_call', jsonb_build_object()
        ),
        jsonb_build_object('backfilled_default_agent', true),
        NOW(),
        NOW()
      FROM accounts
      WHERE NOT EXISTS (
        SELECT 1
        FROM voice_agents
        WHERE voice_agents.account_id = accounts.id
      )
    SQL
  end

  def down
    # no-op: this backfill cannot distinguish migration-set values from Super Admin configured values.
  end
end
