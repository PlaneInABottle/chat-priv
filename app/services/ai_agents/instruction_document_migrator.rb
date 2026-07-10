# frozen_string_literal: true

class AiAgents::InstructionDocumentMigrator
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
    @document = document
  end

  def sections
    document['sections'].is_a?(Array) ? sections_from_legacy_array : sections_from_markdown(document['content'].to_s)
  end

  private

  attr_reader :document

  def sections_from_legacy_array
    Array(document['sections']).each_with_object(empty_sections) do |section, result|
      next unless section.is_a?(Hash)

      data = section.deep_stringify_keys
      source_key = data['key'].to_s
      key = AiAgents::InstructionDocument::SECTION_TITLES.key?(source_key) ? source_key : legacy_section_key(source_key)
      content = legacy_content_to_markdown(data['content'])

      key ? append_section(result, key, content) : append_legacy_custom_section(result, data, content)
    end
  end

  def legacy_section_key(key)
    AiAgents::InstructionDocument::LEGACY_SECTION_KEYS[key]
  end

  def empty_sections
    AiAgents::InstructionDocument::SECTION_ORDER.index_with { '' }
  end

  def append_section(sections, key, content)
    value = content.to_s.strip
    return if value.blank?

    sections[key] = [sections[key], value].compact_blank.join("\n\n")
  end

  def append_legacy_custom_section(sections, data, content)
    title = data['title'].to_s.strip.truncate(80)
    value = title.present? ? "### #{title}\n\n#{content}" : content
    append_section(sections, 'additional', value)
  end

  def sections_from_markdown(content)
    result = empty_sections
    return result if content.blank?

    headings = markdown_h2_headings(content)
    return result.tap { |sections| append_section(sections, 'additional', content) } if headings.empty?

    migrate_markdown_segments(result, content.lines, headings)
  end

  def migrate_markdown_segments(result, lines, headings)
    append_section(result, 'additional', lines.first(headings.first[:start_line] - 1).join)
    headings.each_with_index do |heading, index|
      next_heading = headings[index + 1]
      segment_end = next_heading ? next_heading[:start_line] - 1 : lines.length
      append_markdown_segment(result, lines, heading, segment_end)
    end
    result
  end

  def append_markdown_segment(result, lines, heading, segment_end)
    key = heading_section_key(heading[:title])
    if key
      append_section(result, key, lines[heading[:end_line]...segment_end].join)
    else
      append_section(result, 'additional', lines[(heading[:start_line] - 1)...segment_end].join)
    end
  end

  def heading_section_key(title)
    AiAgents::InstructionDocument::HEADING_SECTION_KEYS[title.downcase.squish]
  end

  def markdown_h2_headings(content)
    document_node = CommonMarker.render_doc(content, [:SOURCEPOS])
    headings = []
    node = document_node.first_child

    while node
      headings << heading_data(node) if node.type == :header && node.header_level == 2
      node = node.next
    end
    headings
  end

  def heading_data(node)
    {
      title: node.to_plaintext.strip,
      start_line: node.sourcepos[:start_line],
      end_line: node.sourcepos[:end_line]
    }
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
