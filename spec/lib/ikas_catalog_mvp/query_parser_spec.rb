# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/ikas_catalog_mvp'

RSpec.describe IkasCatalogMvp::QueryParser do
  it 'folds facet vocabulary once and query text once per facet extraction' do
    parser = described_class.new(facet_vocabulary: { 'color' => %w[red blue] })
    allow(IkasCatalogMvp::Text).to receive(:fold).and_call_original

    2.times do
      text = 'green shirt'
      parser.send(:extract_facets!, text)
    end

    expect(IkasCatalogMvp::Text).to have_received(:fold).with('red').once
    expect(IkasCatalogMvp::Text).to have_received(:fold).with('blue').once
    expect(IkasCatalogMvp::Text).to have_received(:fold).with('green shirt').twice
  end
end
