require 'rails_helper'

RSpec.describe AiAgents::ToolOutputSanitizer do
  it 'keeps and normalizes URLs structurally returned by tools while removing invented URLs' do
    tool_events = [
      {
        'tool' => 'ikas_catalog_search',
        'result' => {
          'candidates' => [{ 'link' => { 'url' => 'https://shop.test/door?"COLOR"=GREY' } }]
        }
      },
      {
        'tool' => 'ikas_lookup_order',
        'result' => {
          'orders' => [{ 'packages' => [{ 'tracking' => { 'tracking_link' => 'https://carrier.test/track/42' } }] }]
        }
      }
    ]
    answer = 'See [the product](https://shop.test/door?"COLOR"=GREY), ' \
             '[tracking](https://carrier.test/track/42), or [an invented page](https://evil.test/fake).'

    sanitized = described_class.new(tool_events: tool_events).sanitize(answer)

    expect(sanitized).to include(
      '[the product](https://shop.test/door?%22COLOR%22=GREY)',
      '[tracking](https://carrier.test/track/42)'
    )
    expect(sanitized).to include('an invented page')
    expect(sanitized).not_to include('https://evil.test/fake')
  end

  it 'repairs only a uniquely identifiable truncated tool URL' do
    tool_events = [{
      'tool' => 'ikas_catalog_search',
      'result' => {
        'candidates' => [{ 'link' => { 'url' => 'https://shop.test/products/door?color=grey' } }]
      }
    }]

    expect(described_class.new(tool_events: tool_events).sanitize('[Product](https://shop.test/products/door?color=gr')).to eq(
      '[Product](https://shop.test/products/door?color=grey)'
    )
    expect(described_class.new(tool_events: tool_events).sanitize('[Product](https://evil.test')).to eq('Product')
  end

  it 'does not restrict ordinary model-only links when no tool ran' do
    answer = 'Read [the guide](https://docs.example.test/start).'

    expect(described_class.new(tool_events: []).sanitize(answer)).to eq(answer)
  end

  it 'can enforce the URL allowlist before a terminal tool performs side effects' do
    answer = 'Continue at [this page](https://invented.example.test/path).'

    expect(described_class.new(tool_events: [], enforce_url_allowlist: true).sanitize(answer)).to eq('Continue at this page.')
  end

  it 'preserves sentence punctuation after a trusted bare URL' do
    tool_events = [{ 'tool' => 'ikas_lookup_order', 'result' => { 'tracking_link' => 'https://carrier.test/track/42' } }]

    expect(described_class.new(tool_events: tool_events).sanitize('Track it at https://carrier.test/track/42.')).to eq(
      'Track it at https://carrier.test/track/42.'
    )
  end
end
