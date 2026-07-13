# frozen_string_literal: true

class AiAgents::InstructionDocument
  VERSION = 3
  SECTION_ORDER = %w[identity business_context tasks rules handoff examples additional].freeze
  SECTION_TITLES = {
    'identity' => 'Identity and purpose',
    'business_context' => 'Business context',
    'tasks' => 'Tasks and conversation flow',
    'rules' => 'Rules and boundaries',
    'handoff' => 'Human handoff',
    'examples' => 'Example conversations',
    'additional' => 'Additional instructions'
  }.freeze
  LEGACY_SECTION_KEYS = {
    'current_instructions' => 'additional'
  }.freeze
  HEADING_SECTION_KEYS = {
    'identity and purpose' => 'identity',
    'business context' => 'business_context',
    'tasks and conversation flow' => 'tasks',
    'rules and boundaries' => 'rules',
    'human handoff' => 'handoff',
    'example conversations' => 'examples',
    'additional instructions' => 'additional',
    'general instructions' => 'additional',
    'current instructions' => 'additional'
  }.freeze
  PROFILE_OPTIONS = {
    'language' => %w[not_set same_as_customer tr en],
    'tone' => %w[not_set natural friendly professional warm concise],
    'formality' => %w[not_set balanced casual formal],
    'response_length' => %w[not_set balanced short detailed]
  }.freeze
  PROFILE_LABELS = {
    'language' => {
      'same_as_customer' => "Use the customer's language",
      'tr' => 'Turkish',
      'en' => 'English'
    },
    'tone' => {
      'natural' => 'Natural',
      'friendly' => 'Friendly',
      'professional' => 'Professional',
      'warm' => 'Warm',
      'concise' => 'Concise'
    },
    'formality' => {
      'balanced' => 'Balanced',
      'casual' => 'Casual',
      'formal' => 'Formal'
    },
    'response_length' => {
      'balanced' => 'Balanced',
      'short' => 'Short',
      'detailed' => 'Detailed'
    }
  }.freeze
  DEFAULT_PROFILE = {
    'language' => 'not_set',
    'tone' => 'not_set',
    'formality' => 'not_set',
    'response_length' => 'not_set'
  }.freeze
  def initialize(document)
    @document = document.is_a?(Hash) ? document.deep_stringify_keys : {}
  end

  def normalized
    {
      'version' => VERSION,
      'profile' => normalized_profile,
      'sections' => normalized_sections
    }
  end

  def compile
    [profile_prompt, prompt_content].compact_blank.join("\n\n")
  end

  def self.from_legacy(prompt)
    new(
      'version' => VERSION,
      'profile' => DEFAULT_PROFILE,
      'sections' => { 'additional' => prompt.to_s }
    ).normalized
  end

  private

  attr_reader :document

  def normalized_profile
    profile = document['profile'].is_a?(Hash) ? document['profile'] : {}
    DEFAULT_PROFILE.each_with_object({}) do |(key, default), result|
      value = profile[key].to_s
      result[key] = PROFILE_OPTIONS[key].include?(value) ? value : default
    end
  end

  def normalized_sections
    @normalized_sections ||= document['sections'].is_a?(Hash) ? sections_from_hash : migrated_sections
  end

  def sections_from_hash
    source = document['sections'].deep_stringify_keys
    SECTION_ORDER.index_with { |key| source[key].to_s }
  end

  def migrated_sections
    AiAgents::InstructionDocumentMigrator.new(document).sections
  end

  def profile_prompt
    profile = normalized_profile
    lines = PROFILE_LABELS.filter_map do |key, labels|
      value = profile[key]
      next if value == 'not_set'

      "- #{profile_field_name(key)}: #{labels[value]}"
    end
    return if lines.empty?

    <<~PROMPT.strip
      ## Language and tone
      #{lines.join("\n")}
    PROMPT
  end

  def profile_field_name(key)
    {
      'language' => 'Reply language',
      'tone' => 'Tone',
      'formality' => 'Formality',
      'response_length' => 'Response length'
    }.fetch(key)
  end

  def prompt_content
    SECTION_ORDER.filter_map do |key|
      content = normalized_sections[key].to_s.strip
      next if content.blank?

      "## #{SECTION_TITLES.fetch(key)}\n\n#{content}"
    end.join("\n\n")
  end
end
