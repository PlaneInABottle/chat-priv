# frozen_string_literal: true

class AiAgents::InstructionDocument
  VERSION = 1
  MAX_SECTIONS = 20
  SECTION_TITLES = {
    'identity' => 'Identity and purpose',
    'business_context' => 'Business context',
    'tasks' => 'Tasks and conversation flow',
    'rules' => 'Rules and boundaries',
    'handoff' => 'Human handoff',
    'examples' => 'Example conversations',
    'current_instructions' => 'Current instructions'
  }.freeze
  PROFILE_OPTIONS = {
    'language' => %w[same_as_customer tr en],
    'tone' => %w[natural friendly professional warm concise],
    'formality' => %w[balanced casual formal],
    'response_length' => %w[balanced short detailed]
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
    'language' => 'same_as_customer',
    'tone' => 'natural',
    'formality' => 'balanced',
    'response_length' => 'balanced'
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
    [profile_prompt, *section_prompts].compact.join("\n\n")
  end

  def self.from_legacy(prompt)
    new(
      'version' => VERSION,
      'profile' => DEFAULT_PROFILE,
      'sections' => [
        {
          'key' => 'current_instructions',
          'title' => SECTION_TITLES['current_instructions'],
          'content' => prompt.to_s,
          'critical' => false,
          'custom' => false
        }
      ]
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
    Array(document['sections']).first(MAX_SECTIONS).filter_map do |section|
      normalize_section(section)
    end
  end

  def normalize_section(section)
    return unless section.is_a?(Hash)

    data = section.deep_stringify_keys
    key = data['key'].to_s.presence || "custom_#{SecureRandom.hex(4)}"
    custom = ActiveModel::Type::Boolean.new.cast(data['custom']) || !SECTION_TITLES.key?(key)
    title = custom ? data['title'].to_s.strip.truncate(80) : SECTION_TITLES[key]
    return if title.blank?

    {
      'key' => key,
      'title' => title,
      'content' => data['content'].to_s,
      'critical' => ActiveModel::Type::Boolean.new.cast(data['critical']),
      'custom' => custom
    }
  end

  def profile_prompt
    profile = normalized_profile
    <<~PROMPT.strip
      ## Language and tone
      - Reply language: #{PROFILE_LABELS['language'][profile['language']]}
      - Tone: #{PROFILE_LABELS['tone'][profile['tone']]}
      - Formality: #{PROFILE_LABELS['formality'][profile['formality']]}
      - Response length: #{PROFILE_LABELS['response_length'][profile['response_length']]}
    PROMPT
  end

  def section_prompts
    normalized_sections.filter_map do |section|
      next if section['content'].blank?

      priority = section['critical'] ? ' — CRITICAL, must always be followed' : ''
      "## #{section['title']}#{priority}\n#{section['content'].strip}"
    end
  end
end
