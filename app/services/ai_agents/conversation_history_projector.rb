# frozen_string_literal: true

# Applies deterministic, UTF-8/grapheme-safe character budgets to compacted
# conversation history before it reaches the orchestrator. Original Message
# records are never modified; this projection exists only in the model prompt.
# There is deliberately no summarization and no tokenizer/model adaptation.
class AiAgents::ConversationHistoryProjector
  MAX_MESSAGES = 20
  MAX_MESSAGE_CHARACTERS = 8_000
  MAX_HISTORY_CHARACTERS = 40_000
  SHORTENING_MARKER = '[...message shortened for AI context...]'
  WHITESPACE_SCAN_GRAPHENES = 200

  def initialize(messages)
    @messages = Array(messages)
  end

  # Packs newest -> oldest under the total budget, then restores chronological
  # order. The newest message is highest priority and is never dropped when its
  # content is non-blank; older messages overflow only into the remaining budget.
  def call
    projected = []
    remaining = MAX_HISTORY_CHARACTERS

    messages.last(MAX_MESSAGES).reverse_each do |raw_entry|
      entry = raw_entry.to_h.symbolize_keys
      content = entry[:content]
      next if content.blank?

      projected_content = project_message(content, remaining, newest: projected.empty?)
      next if projected_content.nil?

      projected << entry.merge(content: projected_content)
      remaining -= grapheme_count(projected_content)
      break if remaining.zero?
    end

    projected.reverse
  end

  private

  attr_reader :messages

  def project_message(content, remaining, newest:)
    count = grapheme_count(content)
    return content if count <= MAX_MESSAGE_CHARACTERS && count <= remaining

    budget = if newest && count > MAX_HISTORY_CHARACTERS
               # One-huge-latest case: the trigger alone exceeds the total budget,
               # so it is truncated to the total budget and older messages drop.
               MAX_HISTORY_CHARACTERS
             else
               [MAX_MESSAGE_CHARACTERS, remaining].min
             end
    truncate_message(content, budget)
  end

  # Preserves a 2/3 head + marker + 1/3 tail split. Cuts are aligned to the
  # nearest whitespace within a bounded grapheme window when one exists, then
  # stripped; the marker counts inside the budget and no grapheme cluster is
  # ever split. When the budget cannot fit the marker, the head alone is kept.
  def truncate_message(content, budget)
    clusters = content.each_grapheme_cluster.to_a
    return clusters.first(budget).join if budget <= SHORTENING_MARKER.length

    body_budget = budget - SHORTENING_MARKER.length
    head_count = (body_budget * 2) / 3
    tail_count = body_budget - head_count
    "#{align_head(clusters.first(head_count))}#{SHORTENING_MARKER}#{align_tail(clusters.last(tail_count))}"
  end

  def align_head(head_clusters)
    window = head_clusters.last(WHITESPACE_SCAN_GRAPHENES)
    last_space_index = window.rindex { |cluster| cluster.match?(/\s/) }
    return head_clusters.join.strip if last_space_index.nil?

    head_clusters.first(head_clusters.length - window.length + last_space_index).join.strip
  end

  def align_tail(tail_clusters)
    window = tail_clusters.first(WHITESPACE_SCAN_GRAPHENES)
    first_space_index = window.index { |cluster| cluster.match?(/\s/) }
    return tail_clusters.join.strip if first_space_index.nil?

    tail_clusters.drop(first_space_index + 1).join.strip
  end

  def grapheme_count(content)
    content.each_grapheme_cluster.count
  end
end
