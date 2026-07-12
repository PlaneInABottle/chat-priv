instructions = website_import.ai_agent.config.to_h['instructions']
current_document = if instructions.present?
                     AiAgents::InstructionDocument.new(instructions).normalized
                   else
                     AiAgents::InstructionDocument.from_legacy(website_import.ai_agent.prompt)
                   end
proposals = website_import.proposed_sections.to_h.deep_stringify_keys
changed_sections = AiAgentWebsiteImport::APPLYABLE_SECTIONS.filter do |key|
  proposals[key].present? && current_document.dig('sections', key).to_s.strip != proposals[key].to_s.strip
end

json.id website_import.id
json.ai_agent_id website_import.ai_agent_id
json.website_url website_import.website_url
json.mode website_import.mode
json.status website_import.status
json.stage website_import.stage
json.source_urls website_import.source_urls
json.proposed_sections proposals
json.changed_sections changed_sections
json.current_document current_document if local_assigns[:include_current_document]
json.current_draft_fingerprint website_import.ai_agent.draft_fingerprint
json.base_draft_fingerprint website_import.base_draft_fingerprint
json.draft_changed website_import.ai_agent.draft_fingerprint != website_import.base_draft_fingerprint
json.stale website_import.stale?
json.error_code website_import.customer_error_code
json.started_at website_import.started_at
json.completed_at website_import.completed_at
json.applied_at website_import.applied_at
json.created_at website_import.created_at
json.updated_at website_import.updated_at
