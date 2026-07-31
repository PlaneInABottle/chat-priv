# frozen_string_literal: true

# Localized prompt labels make this value object longer without adding control-flow complexity.
# rubocop:disable Metrics/ClassLength
class AiAgents::InstructionDocument
  VERSION = 4
  # Documents written at or after this version default to DEFAULT_LOCALE when they carry no
  # explicit locale. It must stay pinned to the version that introduced the default so bumping
  # VERSION never reinterprets the locale of already stored documents.
  DEFAULT_LOCALE_SINCE_VERSION = 4
  DEFAULT_LOCALE = 'tr'
  SUPPORTED_LOCALES = %w[tr en].freeze
  SECTION_ORDER = %w[identity business_context tasks rules handoff examples additional].freeze
  SECTION_TITLES_BY_LOCALE = {
    'en' => {
      'identity' => 'Identity and purpose',
      'business_context' => 'Business context',
      'tasks' => 'Tasks and conversation flow',
      'rules' => 'Rules and boundaries',
      'handoff' => 'Human handoff',
      'examples' => 'Example conversations',
      'additional' => 'Additional instructions'
    },
    'tr' => {
      'identity' => 'Kimlik ve amaç',
      'business_context' => 'İşletme bilgileri',
      'tasks' => 'Görevler ve konuşma akışı',
      'rules' => 'Kurallar ve sınırlar',
      'handoff' => 'İnsan desteğine aktarım',
      'examples' => 'Örnek konuşmalar',
      'additional' => 'Ek talimatlar'
    }
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
    'current instructions' => 'additional',
    'kimlik ve amaç' => 'identity',
    'işletme bilgileri' => 'business_context',
    'görevler ve konuşma akışı' => 'tasks',
    'kurallar ve sınırlar' => 'rules',
    'insan desteğine aktarım' => 'handoff',
    'örnek konuşmalar' => 'examples',
    'ek talimatlar' => 'additional'
  }.freeze
  PROFILE_OPTIONS = {
    'language' => %w[not_set same_as_customer tr en],
    'tone' => %w[not_set natural friendly professional concise],
    'formality' => %w[not_set balanced casual formal],
    'response_length' => %w[not_set balanced short detailed]
  }.freeze
  PROFILE_LABELS_BY_LOCALE = {
    'en' => {
      'language' => {
        'same_as_customer' => "Use the customer's language",
        'tr' => 'Turkish',
        'en' => 'English'
      },
      'tone' => {
        'natural' => 'Natural',
        'friendly' => 'Friendly',
        'professional' => 'Professional',
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
    },
    'tr' => {
      'language' => {
        'same_as_customer' => 'Müşterinin dilini kullan',
        'tr' => 'Türkçe',
        'en' => 'İngilizce'
      },
      'tone' => {
        'natural' => 'Doğal',
        'friendly' => 'Samimi',
        'professional' => 'Profesyonel',
        'concise' => 'Öz'
      },
      'formality' => {
        'balanced' => 'Dengeli',
        'casual' => 'Gündelik',
        'formal' => 'Resmi'
      },
      'response_length' => {
        'balanced' => 'Dengeli',
        'short' => 'Kısa',
        'detailed' => 'Ayrıntılı'
      }
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
      'locale' => normalized_locale,
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
      'locale' => 'en',
      'profile' => DEFAULT_PROFILE,
      'sections' => { 'additional' => prompt.to_s }
    ).normalized
  end

  private

  attr_reader :document

  def normalized_locale
    explicit_locale = document['locale'].to_s
    return explicit_locale if SUPPORTED_LOCALES.include?(explicit_locale)

    profile_language = document.dig('profile', 'language').to_s
    return profile_language if SUPPORTED_LOCALES.include?(profile_language)

    document['version'].to_i >= DEFAULT_LOCALE_SINCE_VERSION ? DEFAULT_LOCALE : 'en'
  end

  def normalized_profile
    profile = document['profile'].is_a?(Hash) ? document['profile'] : {}
    DEFAULT_PROFILE.each_with_object({}) do |(key, default), result|
      value = profile[key].to_s
      value = 'friendly' if key == 'tone' && value == 'warm'
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
    lines = profile_labels.filter_map do |key, labels|
      value = profile[key]
      next if value == 'not_set'

      "- #{profile_field_name(key)}: #{labels[value]}"
    end
    return if lines.empty?

    <<~PROMPT.strip
      ## #{profile_heading}
      #{lines.join("\n")}
    PROMPT
  end

  def profile_field_name(key)
    profile_field_names.fetch(key)
  end

  def prompt_content
    SECTION_ORDER.filter_map do |key|
      content = normalized_sections[key].to_s.strip
      next if content.blank?

      "## #{section_titles.fetch(key)}\n\n#{content}"
    end.join("\n\n")
  end

  def section_titles
    SECTION_TITLES_BY_LOCALE.fetch(normalized_locale)
  end

  def profile_labels
    PROFILE_LABELS_BY_LOCALE.fetch(normalized_locale)
  end

  def profile_heading
    normalized_locale == 'tr' ? 'Dil ve üslup' : 'Language and tone'
  end

  def profile_field_names
    if normalized_locale == 'tr'
      return {
        'language' => 'Yanıt dili',
        'tone' => 'Üslup',
        'formality' => 'Resmiyet',
        'response_length' => 'Yanıt uzunluğu'
      }
    end

    {
      'language' => 'Reply language',
      'tone' => 'Tone',
      'formality' => 'Formality',
      'response_length' => 'Response length'
    }
  end
end
# rubocop:enable Metrics/ClassLength
