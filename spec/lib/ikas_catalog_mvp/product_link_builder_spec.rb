# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/ikas_catalog_mvp'

RSpec.describe IkasCatalogMvp::ProductLinkBuilder do
  def storefront(overrides = {})
    {
      'id' => 'storefront-public',
      'name' => 'Public Storefront',
      'deleted' => false,
      'salesChannelId' => 'sales-channel-public',
      'domains' => [{ 'id' => 'domain-public', 'name' => 'store.example.com', 'isDefault' => true }],
      'routings' => [{ 'domain' => 'store.example.com', 'path' => 'katalog', 'currencyCode' => 'TRY', 'currencySymbol' => '₺' }]
    }.merge(overrides)
  end

  def product
    {
      'id' => 'product-1',
      'salesChannelIds' => ['sales-channel-public'],
      'hiddenSalesChannelIds' => [],
      'metaData' => { 'slug' => 'balcony-screen', 'canonicals' => [] }
    }
  end

  it 'accepts an eligible storefront and exposes its linked fields' do
    builder = described_class.new(storefronts: [storefront])

    expect(builder.eligible_storefronts).to contain_exactly(
      include(
        'id' => 'storefront-public',
        'name' => 'Public Storefront',
        'sales_channel_id' => 'sales-channel-public',
        'domain' => 'store.example.com',
        'path' => 'katalog',
        'currency_code' => 'TRY',
        'currency_symbol' => '₺'
      )
    )
    expect(builder.product_visible?(product)).to be(true)
    expect(builder.link_fields_for(product)).to include(
      'product_url' => 'https://store.example.com/katalog/balcony-screen',
      'storefront_id' => 'storefront-public',
      'storefront_domain' => 'store.example.com',
      'storefront_sales_channel_id' => 'sales-channel-public'
    )
  end

  it 'rejects a deleted storefront' do
    builder = described_class.new(storefronts: [storefront('deleted' => true)])

    expect(builder.eligible_storefronts).to be_empty
    expect(builder.product_visible?(product)).to be(false)
    expect(builder.link_fields_for(product)).to eq({})
  end

  it 'rejects a storefront with a truthy deleted value' do
    [1, '1', 'true', 'True'].each do |deleted_value|
      builder = described_class.new(storefronts: [storefront('deleted' => deleted_value)])

      expect(builder.eligible_storefronts).to be_empty
    end
  end

  it 'accepts a storefront without a deleted key for backward compatibility' do
    legacy_storefront = storefront.delete_if { |key, _| key == 'deleted' }
    builder = described_class.new(storefronts: [legacy_storefront])

    expect(builder.eligible_storefronts.map { |row| row.fetch('id') }).to contain_exactly('storefront-public')
  end

  it 'only keeps non-deleted storefronts when multiple are present' do
    builder = described_class.new(
      storefronts: [
        storefront,
        storefront('id' => 'storefront-deleted', 'deleted' => true),
        storefront('id' => 'storefront-legacy')
      ]
    )

    expect(builder.eligible_storefronts.map { |entry| entry.fetch('id') })
      .to contain_exactly('storefront-public', 'storefront-legacy')
  end

  it 'requires a domain and a sales channel to build a link' do
    builder = described_class.new(storefronts: [storefront('domains' => [], 'salesChannelId' => '')])

    expect(builder.eligible_storefronts).to be_empty
  end
end
