# frozen_string_literal: true

class AiAgents::EvaluationTextSanitizer
  REPLACEMENTS = {
    /\bhuman_handoff aracını kullanır\b/i => 'konuşmayı bir temsilciye aktarır',
    /\bhuman_handoff aracı\b/i => 'insana aktarma özelliği',
    /\b(?:shared_knowledge|search_knowledge)\b/i => 'verified business information',
    /\bhuman_handoff\b/i => 'transfer the conversation to a human',
    /\bikas_catalog_search\b/i => 'search the connected product catalog',
    /\bikas_lookup_order\b/i => 'check the connected order system'
  }.freeze

  def self.sanitize(value)
    REPLACEMENTS.reduce(value.to_s.strip) do |text, (pattern, replacement)|
      text.gsub(pattern, replacement)
    end
  end
end
