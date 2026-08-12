# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgents::ConversationHistoryProjector do
  def project(messages)
    described_class.new(messages).call
  end

  describe 'message count cap' do
    it 'keeps up to 20 chronological messages unchanged' do
      messages = (1..20).map { |index| { role: 'user', content: "Message #{index}" } }

      expect(project(messages)).to eq(messages)
    end

    it 'drops the oldest messages beyond 20' do
      messages = (1..21).map { |index| { role: 'user', content: "Message #{index}" } }

      expect(project(messages).map { |entry| entry[:content] }).to eq((2..21).map { |index| "Message #{index}" })
    end
  end

  describe 'character budgets' do
    it 'keeps messages within the per-message budget unchanged' do
      messages = [{ role: 'user', content: 'a' * 7_500 }]

      expect(project(messages).first[:content]).to eq('a' * 7_500)
    end

    it 'truncates an oversized message to the per-message budget with head, marker, and tail' do
      content = "#{('Word fragment ' * 690)}FINAL"
      messages = [{ role: 'user', content: content }]
      output = project(messages).first[:content]

      expect(output.grapheme_clusters.length).to be <= described_class::MAX_MESSAGE_CHARACTERS
      expect(output).to include(described_class::SHORTENING_MARKER)
      expect(output.split(described_class::SHORTENING_MARKER).length).to eq(2)
      expect(output).to start_with('Word fragment')
      expect(output).to end_with('FINAL')
    end

    it 'counts the marker inside the budget' do
      messages = [{ role: 'user', content: 'x' * 9_000 }]

      expect(project(messages).first[:content].length).to eq(described_class::MAX_MESSAGE_CHARACTERS)
    end

    it 'keeps the total projected history within the total budget' do
      messages = (1..20).map { |index| { role: 'user', content: "#{index.to_s.rjust(2, '0')}:#{'x' * 2_000}" } }

      expect(project(messages).sum { |entry| entry[:content].grapheme_clusters.length }).to eq(
        described_class::MAX_HISTORY_CHARACTERS
      )
      expect(project(messages).length).to eq(20)
    end

    it 'truncates a newest trigger that alone exceeds the total budget and drops older messages' do
      messages = [{ role: 'user', content: 'Old message' }, { role: 'user', content: 'Huge' * 40_000 }]
      output = project(messages).first[:content]

      expect(project(messages).length).to eq(1)
      expect(output.grapheme_clusters.length).to eq(described_class::MAX_HISTORY_CHARACTERS)
      expect(output).to include(described_class::SHORTENING_MARKER)
    end

    it 'bounds a huge old message after a normal newer message' do
      messages = [{ role: 'user', content: 'Huge' * 40_000 }, { role: 'user', content: 'Newer trigger' }]

      expect(project(messages).last[:content]).to eq('Newer trigger')
      expect(project(messages).first[:content].grapheme_clusters.length).to be <= described_class::MAX_MESSAGE_CHARACTERS
      expect(project(messages).first[:content]).to include(described_class::SHORTENING_MARKER)
    end
  end

  describe 'grapheme safety' do
    it 'never splits emoji grapheme clusters' do
      messages = [{ role: 'user', content: '😀' * 9_000 }]
      head, tail = project(messages).first[:content].split(described_class::SHORTENING_MARKER)

      expect(head.each_grapheme_cluster.all?('😀')).to be(true)
      expect(tail.each_grapheme_cluster.all?('😀')).to be(true)
    end

    it 'never splits combining sequences or ZWJ families' do
      messages = [{ role: 'user', content: ("e\u0301" * 9_000) + ('👨‍👩‍👧‍👦' * 100) }]
      head, tail = project(messages).first[:content].split(described_class::SHORTENING_MARKER)

      expect(head.each_grapheme_cluster.all?("e\u0301")).to be(true)
      expect(tail.each_grapheme_cluster.all? { |cluster| cluster == "e\u0301" || cluster == '👨‍👩‍👧‍👦' }).to be(true)
    end

    it 'preserves Turkish characters through truncation' do
      messages = [{ role: 'user', content: "#{('ğışİçöü ' * 1_000)}FINAL" }]
      output = project(messages).first[:content]

      expect(output).to include('ğ', 'ş', 'İ', 'ç', 'ö', 'ü')
      expect(output.grapheme_clusters.length).to be <= described_class::MAX_MESSAGE_CHARACTERS
      expect(output).to end_with('FINAL')
    end
  end

  describe 'ordering and shape' do
    it 'restores chronological order and preserves roles and extra fields' do
      messages = [
        { role: 'user', content: 'Old' },
        { role: 'assistant', content: 'Mid', catalog_presentation_id: 'p-1' },
        { role: 'user', content: 'Huge' * 20_000 },
        { role: 'user', content: 'Newest' }
      ]

      expect(project(messages).map { |entry| entry[:role] }).to eq(%w[user assistant user user])
      expect(project(messages).first[:content]).to eq('Old')
      expect(project(messages).last[:content]).to eq('Newest')
      expect(project(messages)[1][:catalog_presentation_id]).to eq('p-1')
      expect(project(messages)[2][:content]).to include(described_class::SHORTENING_MARKER)
    end

    it 'passes compacted product group content through coherently' do
      messages = [
        { role: 'user', content: 'Old' },
        { role: 'assistant', content: "1. Kırmızı Sineklik\n2. Mavi Sineklik", catalog_presentation_id: 'p-1' },
        { role: 'user', content: 'Show more' }
      ]

      expect(project(messages).map { |entry| entry[:content] }).to eq(
        ['Old', "1. Kırmızı Sineklik\n2. Mavi Sineklik", 'Show more']
      )
      expect(project(messages)[1][:catalog_presentation_id]).to eq('p-1')
    end

    it 'skips blank content defensively' do
      messages = [
        { role: 'user', content: '   ' },
        { role: 'user', content: nil },
        { role: 'user', content: '' },
        { role: 'user', content: 'Real' }
      ]

      expect(project(messages).map { |entry| entry[:content] }).to eq(['Real'])
    end

    it 'does not mutate the input hashes' do
      messages = [{ role: 'user', content: 'Huge' * 20_000 }, { role: 'user', content: 'Newest' }]
      original = messages.map(&:dup)

      project(messages)

      expect(messages).to eq(original)
    end

    it 'performs no database writes' do
      messages = [{ role: 'user', content: 'Hello' }]

      expect { project(messages) }.not_to change(Message, :count)
    end
  end

  describe 'degenerate budgets' do
    it 'keeps only the head without the marker when the budget cannot fit the marker' do
      expect(described_class.new([]).send(:truncate_message, 'abcdef', 5)).to eq('abcde')
    end
  end
end
