# frozen_string_literal: true

class AiAgents::InstructionDocument
  VERSION = 2
  MAX_SECTIONS = 20
  SECTION_TITLES = {
    'identity' => 'Identity and purpose',
    'business_context' => 'Business context',
    'tasks' => 'Tasks and conversation flow',
    'rules' => 'Rules and boundaries',
    'handoff' => 'Human handoff',
    'examples' => 'Example conversations',
    'current_instructions' => 'General instructions'
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
  NODE_RENDERERS = {
    'h2' => :render_h2,
    'h3' => :render_h3,
    'p' => :render_paragraph,
    'strong' => :render_strong,
    'b' => :render_strong,
    'em' => :render_emphasis,
    'i' => :render_emphasis,
    'ul' => :render_unordered_list,
    'ol' => :render_ordered_list,
    'li' => :render_children,
    'a' => :render_link,
    'br' => :render_break
  }.freeze

  def initialize(document)
    @document = document.is_a?(Hash) ? document.deep_stringify_keys : {}
  end

  def normalized
    {
      'version' => VERSION,
      'profile' => normalized_profile,
      'content' => normalized_content
    }
  end

  def compile
    [profile_prompt, prompt_content].compact_blank.join("\n\n")
  end

  def self.from_legacy(prompt)
    new(
      'version' => VERSION,
      'profile' => DEFAULT_PROFILE,
      'content' => "## #{SECTION_TITLES['current_instructions']}\n\n#{prompt}"
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

  def normalized_content
    @normalized_content ||= (document['content'].presence || content_from_legacy_sections).to_s
  end

  def content_from_legacy_sections
    Array(document['sections']).first(MAX_SECTIONS).filter_map do |section|
      next unless section.is_a?(Hash)

      data = section.deep_stringify_keys
      key = data['key'].to_s
      title = SECTION_TITLES[key] || data['title'].to_s.strip.truncate(80)
      next if title.blank?

      "## #{title}\n\n#{legacy_content_to_markdown(data['content'])}"
    end.join("\n\n")
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
    normalized_content.strip
  end

  def legacy_content_to_markdown(content)
    return content.to_s unless content.to_s.match?(%r{</?[a-z][^>]*>}i)

    fragment = Nokogiri::HTML5.fragment(content.to_s)
    fragment.children.map { |node| render_node(node) }.join.strip
  end

  def render_node(node)
    return node.text if node.text?

    children = node.children.map { |child| render_node(child) }.join
    renderer = NODE_RENDERERS[node.name]
    renderer ? send(renderer, node, children) : children
  end

  def render_h2(_node, children) = "\n\n## #{children.strip}\n"
  def render_h3(_node, children) = "\n\n### #{children.strip}\n"
  def render_paragraph(_node, children) = "#{children.strip}\n\n"
  def render_strong(_node, children) = "**#{children}**"
  def render_emphasis(_node, children) = "*#{children}*"
  def render_children(_node, children) = children
  def render_link(node, children) = "#{children} (#{node['href']})"
  def render_break(_node, _children) = "\n"

  def render_unordered_list(node, _children)
    "#{node.element_children.map { |item| "- #{render_node(item).strip}" }.join("\n")}\n\n"
  end

  def render_ordered_list(node, _children)
    "#{node.element_children.map.with_index(1) { |item, index| "#{index}. #{render_node(item).strip}" }.join("\n")}\n\n"
  end
end
