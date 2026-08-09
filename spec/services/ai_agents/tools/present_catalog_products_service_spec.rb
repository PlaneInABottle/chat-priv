require 'rails_helper'

RSpec.describe AiAgents::Tools::PresentCatalogProductsService do
  subject(:service) do
    described_class.new(
      account: account,
      tool_events: tool_events,
      resolver: resolver
    )
  end

  let(:account) { create(:account) }
  let(:resolver) { instance_double(Integrations::Ikas::Catalog::ItemImagesResolver) }
  let(:red_images) { %w[https://cdn.myikas.com/red-main.webp https://cdn.myikas.com/red-side.webp] }
  let(:gallery_images) do
    %w[https://cdn.myikas.com/1.webp https://cdn.myikas.com/2.webp https://cdn.myikas.com/3.webp https://cdn.myikas.com/4.webp]
  end
  let(:tool_events) do
    [{
      'tool' => 'ikas_catalog_search',
      'status' => 'ok',
      'result' => {
        'result_type' => 'show_candidates',
        'candidates' => [
          {
            'item_id' => 'variant:red',
            'display_name' => 'Red Screen',
            'image' => { 'available' => true, 'count' => 2 },
            'configuration' => {
              'options' => [
                { 'type' => 'dimension', 'axis' => 'width', 'unit' => 'cm', 'max' => 80 },
                { 'type' => 'dimension', 'axis' => 'height', 'unit' => 'cm', 'max' => 150 }
              ]
            }
          },
          { 'item_id' => 'variant:blue', 'display_name' => 'Blue Screen', 'image' => { 'available' => true, 'count' => 1 } }
        ]
      }
    }]
  end

  it 'builds a terminal display-only presentation from verified catalog items' do
    resolved = [
      catalog_item('variant:red', 'Red Screen', red_images),
      catalog_item('variant:blue', 'Blue Screen', ['https://cdn.myikas.com/blue-main.webp'])
    ]
    allow(resolver).to receive(:resolve).with(item_ids: %w[variant:red variant:blue]).and_return(resolved)

    result = service.call(args: {
                            'mode' => 'products',
                            'catalog_item_ids' => %w[variant:red variant:blue],
                            'customer_message' => 'Balkon kapınız için uygun ürünlerimiz aşağıda.'
                          })

    expect(result).to include(
      status: 'ok',
      terminal_action: 'present_catalog_products',
      customer_message: 'Balkon kapınız için uygun ürünlerimiz aşağıda.'
    )
    expect(result.dig(:presentation, :content_type)).to eq('catalog_products')
    expect(result.dig(:presentation, :items).map { |item| item[:item_id] }).to eq(%w[variant:red variant:blue])
    expect(result.dig(:presentation, :items).first[:images]).to eq(['https://cdn.myikas.com/red-main.webp'])
    expect(result.dig(:presentation, :items).first[:maximum_dimensions]).to eq(width: 80, height: 150, unit: 'cm')
    expect(result.dig(:presentation, :items).first).not_to include(:value, :options, :selected)
  end

  it 'uses up to three ordered photos for an explicitly requested product gallery' do
    allow(resolver).to receive(:resolve).with(item_ids: ['variant:red']).and_return([
                                                                                      catalog_item('variant:red', 'Red Screen', gallery_images)
                                                                                    ])

    result = service.call(args: {
                            'mode' => 'product_gallery',
                            'catalog_item_ids' => ['variant:red'],
                            'customer_message' => 'Bu ürünümüzün diğer görselleri aşağıda.'
                          })

    expect(result.dig(:presentation, :items).one?).to be(true)
    expect(result.dig(:presentation, :items, 0, :images)).to eq(
      %w[https://cdn.myikas.com/1.webp https://cdn.myikas.com/2.webp https://cdn.myikas.com/3.webp]
    )
  end

  it 'rejects unknown item IDs and more than three products recoverably' do
    allow(resolver).to receive(:resolve)

    unknown = service.call(args: {
                             'mode' => 'products',
                             'catalog_item_ids' => ['variant:unknown'],
                             'customer_message' => 'Ürünlerimiz aşağıda.'
                           })
    too_many = service.call(args: {
                              'mode' => 'products',
                              'catalog_item_ids' => %w[variant:red variant:blue variant:three variant:four],
                              'customer_message' => 'Ürünlerimiz aşağıda.'
                            })

    expect(unknown).to include(status: 'error', error_code: 'unknown_catalog_item', recoverable: true)
    expect(too_many).to include(status: 'error', error_code: 'invalid_product_count', recoverable: true)
    expect(resolver).not_to have_received(:resolve)
  end

  it 'rejects catalog candidates that do not have an image' do
    no_image_events = tool_events.deep_dup
    no_image_events.first.dig('result', 'candidates').first['image']['available'] = false
    service = described_class.new(account: account, tool_events: no_image_events, resolver: resolver)
    allow(resolver).to receive(:resolve)

    result = service.call(args: {
                            mode: 'products',
                            catalog_item_ids: ['variant:red'],
                            customer_message: 'Ürünümüz aşağıda.'
                          })

    expect(result).to include(status: 'error', error_code: 'catalog_images_unavailable', recoverable: true)
    expect(resolver).not_to have_received(:resolve)
  end

  it 'continues with products that were not shown in an earlier presentation' do
    ai_agent = create(:ai_agent, account: account)
    conversation = create(:ai_agent_test_conversation, account: account, ai_agent: ai_agent)
    conversation.append_message(
      role: 'assistant',
      content: 'İlk ürünümüz aşağıda.',
      metadata: {
        terminal_action: 'present_catalog_products',
        tool_result: {
          presentation: {
            id: 'previous-presentation',
            items: [{ item_id: 'variant:red', display_name: 'Red Screen' }]
          }
        }
      }
    )
    continuation_service = described_class.new(
      account: account,
      conversation: conversation,
      tool_events: tool_events,
      resolver: resolver
    )
    allow(resolver).to receive(:resolve).with(item_ids: ['variant:blue']).and_return([
                                                                                       catalog_item('variant:blue', 'Blue Screen', ['https://cdn.myikas.com/blue-main.webp'])
                                                                                     ])

    result = continuation_service.call(args: {
                                         mode: 'products',
                                         catalog_item_ids: ['variant:blue'],
                                         customer_message: 'Diğer ürünümüz aşağıda.',
                                         continue_previous: true
                                       })
    repeated = continuation_service.call(args: {
                                           mode: 'products',
                                           catalog_item_ids: ['variant:red'],
                                           customer_message: 'Diğer ürünümüz aşağıda.',
                                           continue_previous: true
                                         })

    expect(result).to include(status: 'ok')
    expect(result.dig(:presentation, :continuation_of)).to eq('previous-presentation')
    expect(repeated).to include(status: 'error', error_code: 'repeated_catalog_item', recoverable: true)
  end

  it 'continues a product gallery after the images already displayed' do
    ai_agent = create(:ai_agent, account: account)
    conversation = create(:ai_agent_test_conversation, account: account, ai_agent: ai_agent)
    conversation.append_message(
      role: 'assistant',
      content: 'Ürünümüzün ilk görseli aşağıda.',
      metadata: {
        terminal_action: 'present_catalog_products',
        tool_result: {
          presentation: {
            id: 'first-gallery',
            items: [{ item_id: 'variant:red', display_name: 'Red Screen', images: ['https://cdn.myikas.com/1.webp'] }]
          }
        }
      }
    )
    gallery_service = described_class.new(
      account: account,
      conversation: conversation,
      tool_events: tool_events,
      resolver: resolver
    )
    allow(resolver).to receive(:resolve).with(item_ids: ['variant:red']).and_return([
                                                                                      catalog_item('variant:red', 'Red Screen', gallery_images)
                                                                                    ])

    result = gallery_service.call(args: {
                                    mode: 'product_gallery',
                                    catalog_item_ids: ['variant:red'],
                                    customer_message: 'Ürünümüzün diğer görselleri aşağıda.',
                                    continue_previous: true
                                  })

    expect(result.dig(:presentation, :continuation_of)).to eq('first-gallery')
    expect(result.dig(:presentation, :items, 0, :images)).to eq(
      %w[https://cdn.myikas.com/2.webp https://cdn.myikas.com/3.webp https://cdn.myikas.com/4.webp]
    )
  end

  it 'reads prior product groups from a live conversation before continuing' do
    conversation = create(:conversation, account: account)
    create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      message_type: 'outgoing',
      content_attributes: {
        'ai_agent' => {
          'catalog_presentation' => {
            'id' => 'live-presentation',
            'sequence' => 1,
            'total' => 1,
            'item_id' => 'variant:red'
          }
        }
      }
    )
    continuation_service = described_class.new(
      account: account,
      conversation: conversation,
      tool_events: tool_events,
      resolver: resolver
    )
    allow(resolver).to receive(:resolve).with(item_ids: ['variant:blue']).and_return([
                                                                                       catalog_item('variant:blue', 'Blue Screen', ['https://cdn.myikas.com/blue-main.webp'])
                                                                                     ])

    result = continuation_service.call(args: {
                                         mode: 'products',
                                         catalog_item_ids: ['variant:blue'],
                                         customer_message: 'Diğer ürünümüz aşağıda.',
                                         continue_previous: true
                                       })

    expect(result).to include(status: 'ok')
    expect(result.dig(:presentation, :continuation_of)).to eq('live-presentation')
  end

  it 'continues a live gallery by image identity after a partial preparation failure' do
    conversation = create(:conversation, account: account)
    %w[https://cdn.myikas.com/2.webp https://cdn.myikas.com/3.webp].each_with_index do |image_url, index|
      create(
        :message,
        account: account,
        inbox: conversation.inbox,
        conversation: conversation,
        message_type: 'outgoing',
        content_attributes: {
          'ai_agent' => {
            'catalog_presentation' => {
              'id' => 'partial-gallery',
              'sequence' => index + 1,
              'total' => 2,
              'item_id' => 'variant:red',
              'image_attached' => true,
              'image_key' => Digest::SHA256.hexdigest(image_url)
            }
          }
        }
      )
    end
    gallery_service = described_class.new(
      account: account,
      conversation: conversation,
      tool_events: tool_events,
      resolver: resolver
    )
    allow(resolver).to receive(:resolve).with(item_ids: ['variant:red']).and_return([
                                                                                      catalog_item('variant:red', 'Red Screen', gallery_images)
                                                                                    ])

    result = gallery_service.call(args: {
                                    mode: 'product_gallery',
                                    catalog_item_ids: ['variant:red'],
                                    customer_message: 'Kalan görsellerimiz aşağıda.',
                                    continue_previous: true
                                  })

    expect(result.dig(:presentation, :items, 0, :images)).to contain_exactly(
      'https://cdn.myikas.com/1.webp',
      'https://cdn.myikas.com/4.webp'
    )
  end

  def catalog_item(item_id, name, images)
    {
      item_id: item_id,
      display_name: name,
      price: { amount: 499, currency: 'TRY', final_total_known: true },
      link: { url: "https://store.example/#{item_id}" },
      image_scope: 'variant',
      images: images
    }
  end
end
