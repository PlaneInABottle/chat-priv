json.status @website_import&.status || (@ai_agent ? 'fallback' : 'not_started')
json.stage @website_import&.stage || (@ai_agent ? 'complete' : 'queued')
json.onboarding_step Current.account.onboarding_step
if @ai_agent
  json.ai_agent do
    json.id @ai_agent.id
    json.name @ai_agent.name
  end
end
if @website_import
  json.website_import do
    json.partial! 'api/v1/accounts/ai_agent_website_imports/website_import', website_import: @website_import
  end
end
