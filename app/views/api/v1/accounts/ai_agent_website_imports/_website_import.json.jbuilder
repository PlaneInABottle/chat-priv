current_document = AiAgents::InstructionDocument.new(website_import.ai_agent.config.to_h['instructions']).normalized
proposals = website_import.proposed_sections.to_h.deep_stringify_keys
changed_sections = proposals.filter_map do |key, value|
  key if value.present? && current_document.dig('sections', key).to_s.strip != value.to_s.strip
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
json.current_draft_fingerprint website_import.ai_agent.draft_fingerprint
json.error_code website_import.error_code
json.error_message website_import.error_message
json.started_at website_import.started_at
json.completed_at website_import.completed_at
json.applied_at website_import.applied_at
json.created_at website_import.created_at
json.updated_at website_import.updated_at
