require 'rails_helper'

RSpec.describe AiAgents::CatalogImagePreparer do
  it 'downloads a trusted Ikas image and normalizes it to a bounded JPEG attachment' do
    source = Tempfile.new(['catalog-source', '.png'], binmode: true)
    source.write(File.binread(Rails.root.join('spec/assets/sample.png')))
    source.rewind
    allow(SafeFetch).to receive(:fetch).and_yield(
      SafeFetch::Result.new(tempfile: source, filename: 'sample.png', content_type: 'image/png')
    )

    prepared = described_class.new.prepare(
      'https://cdn.myikas.com/images/05d8a2b7-89af-41b3-b47f-b091868cfd8c/5a9ebce4-8b06-4b92-9ed2-a8ffadb435de/1080/sample.webp'
    )

    expect(prepared).to have_attributes(content_type: 'image/jpeg')
    expect(prepared.tempfile.size).to be <= described_class::MAX_OUTPUT_BYTES
    expect(Marcel::MimeType.for(prepared.tempfile, name: prepared.filename)).to eq('image/jpeg')
  ensure
    prepared&.close!
    source&.close!
  end

  it 'rejects non-Ikas and non-HTTPS image origins before fetching' do
    preparer = described_class.new
    allow(SafeFetch).to receive(:fetch)

    expect { preparer.prepare('http://cdn.myikas.com/image.webp') }.to raise_error(AiAgents::CatalogImagePreparer::InvalidSource)
    expect { preparer.prepare('https://example.com/image.webp') }.to raise_error(AiAgents::CatalogImagePreparer::InvalidSource)
    expect { preparer.prepare('https://cdn.myikas.com:444/image.webp') }.to raise_error(AiAgents::CatalogImagePreparer::InvalidSource)
    expect { preparer.prepare('https://cdn.myikas.com/unexpected/image.webp') }.to raise_error(AiAgents::CatalogImagePreparer::InvalidSource)
    expect(SafeFetch).not_to have_received(:fetch)
  end

  it 'rejects images whose decoded dimensions exceed the processing limit' do
    source = Tempfile.new(['catalog-source', '.png'], binmode: true)
    source.write(File.binread(Rails.root.join('spec/assets/sample.png')))
    source.rewind
    allow(SafeFetch).to receive(:fetch).and_yield(
      SafeFetch::Result.new(tempfile: source, filename: 'sample.png', content_type: 'image/png')
    )
    image = instance_double(MiniMagick::Image, width: 50_000, height: 50_000, destroy!: true)
    allow(MiniMagick::Image).to receive(:open).and_return(image)

    expect do
      described_class.new.prepare(
        'https://cdn.myikas.com/images/05d8a2b7-89af-41b3-b47f-b091868cfd8c/5a9ebce4-8b06-4b92-9ed2-a8ffadb435de/1080/sample.webp'
      )
    end.to raise_error(AiAgents::CatalogImagePreparer::InvalidImage, /dimensions exceed/)
  ensure
    source&.close!
  end
end
