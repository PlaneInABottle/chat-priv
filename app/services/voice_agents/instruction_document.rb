# frozen_string_literal: true

class VoiceAgents::InstructionDocument
  VERSION = AiAgents::InstructionDocument::VERSION
  MAX_COMPILED_LENGTH = 50_000
  SECTION_ORDER = %w[business_context tasks rules].freeze
  DOCUMENT_KEYS = %w[version locale profile sections].freeze

  def initialize(document)
    raise ArgumentError, 'Voice instruction document must be an object' unless document.is_a?(Hash)

    @document = document.deep_stringify_keys
  end

  def normalized
    validate!
    {
      'version' => VERSION,
      'locale' => document.fetch('locale'),
      'profile' => AiAgents::InstructionDocument::DEFAULT_PROFILE.keys.index_with { |key| document.fetch('profile').fetch(key) },
      'sections' => SECTION_ORDER.index_with { |key| document.fetch('sections').fetch(key) }
    }
  end

  def compile
    canonical = normalized
    shared_sections = AiAgents::InstructionDocument::SECTION_ORDER.index_with { |key| canonical['sections'][key].to_s }
    AiAgents::InstructionDocument.new(canonical.merge('sections' => shared_sections)).compile
  end

  def content_length
    compile.length
  end

  def validate_compiled_length!
    if content_length > MAX_COMPILED_LENGTH
      raise ArgumentError, "Compiled Voice instructions are too long (maximum is #{MAX_COMPILED_LENGTH} characters)"
    end

    self
  end

  def self.from_legacy(prompt, locale: 'en')
    raise ArgumentError, 'Legacy Voice prompt must be a string' unless prompt.is_a?(String)

    new(
      'version' => VERSION,
      'locale' => locale,
      'profile' => AiAgents::InstructionDocument::DEFAULT_PROFILE,
      'sections' => { 'business_context' => '', 'tasks' => '', 'rules' => prompt }
    ).normalized
  end

  private

  attr_reader :document

  def validate!
    reject_unknown_keys!(document, DOCUMENT_KEYS, 'document')
    raise ArgumentError, 'Voice instruction version must be 4' unless document['version'] == VERSION
    raise ArgumentError, 'Voice instruction locale is invalid' unless AiAgents::InstructionDocument::SUPPORTED_LOCALES.include?(document['locale'])

    validate_hash!('profile')
    validate_hash!('sections')
    validate_profile!
    validate_sections!
  end

  def validate_profile!
    reject_unknown_keys!(document['profile'], AiAgents::InstructionDocument::DEFAULT_PROFILE.keys, 'profile')
    AiAgents::InstructionDocument::PROFILE_OPTIONS.each do |key, options|
      raise ArgumentError, "Voice instruction profile #{key} is invalid" unless options.include?(document['profile'][key])
    end
  end

  def validate_sections!
    reject_unknown_keys!(document['sections'], SECTION_ORDER, 'section')
    SECTION_ORDER.each do |key|
      raise ArgumentError, "Voice instruction section #{key} must be a string" unless document['sections'][key].is_a?(String)
    end
  end

  def validate_hash!(key)
    raise ArgumentError, "Voice instruction #{key} must be an object" unless document[key].is_a?(Hash)
  end

  def reject_unknown_keys!(value, allowed, name)
    unknown = value.keys - allowed
    raise ArgumentError, "Unknown #{name} key: #{unknown.first}" if unknown.any?
  end
end
