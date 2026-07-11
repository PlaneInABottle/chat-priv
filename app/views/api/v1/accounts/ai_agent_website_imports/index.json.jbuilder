json.array! @website_imports do |website_import|
  json.partial! 'api/v1/accounts/ai_agent_website_imports/website_import', website_import: website_import
end
