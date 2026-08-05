require 'rails_helper'

RSpec.describe MarketingController do
  contract_files = {
    'app/javascript/entrypoints/marketing.scss' => 'b081e46aad1f1332f8f45309b4eba2870600f5c63280636b693c8c2dbd2594b4',
    'public/marketing/assets/pexels-6046230-black-sweater-crop.jpg' =>
      '24bd0bd3e4a67f22e3ab1a7baefea24076e9846986f0bc1da545e0aac47d9fe0',
    'public/marketing/assets/ikas-official-wordmark.svg' =>
      '791cfbaa104fe90a9d11f57f8c7872be9b41fafd1a9a9aad0592e64fa2206ffc'
  }

  it 'preserves the approved stylesheet and visual asset bytes' do
    contract_files.each do |relative_path, expected_sha|
      path = Rails.root.join(relative_path)

      expect(path).to exist
      expect(Digest::SHA256.file(path).hexdigest).to eq(expected_sha)
    end
  end

  it 'keeps explicit reduced-motion and mobile recomposition rules' do
    stylesheet = Rails.root.join('app/javascript/entrypoints/marketing.scss').read

    expect(stylesheet).to include('@media (max-width: 800px)')
    expect(stylesheet).to include('@media (prefers-reduced-motion: reduce)')
    expect(stylesheet).to include('.control-grid article { min-height: 156px;')
    expect(stylesheet).to include('.text-link { display: none; }')
  end

  it 'keeps English and Turkish marketing locale keys aligned' do
    flatten_keys = lambda do |value, prefix = nil|
      value.each_with_object([]) do |(key, nested_value), keys|
        path = [prefix, key].compact.join('.')
        keys.concat(nested_value.is_a?(Hash) ? flatten_keys.call(nested_value, path) : [path])
      end
    end

    en_keys = flatten_keys.call(I18n.t('marketing', locale: :en))
    tr_keys = flatten_keys.call(I18n.t('marketing', locale: :tr))

    expect(en_keys).to match_array(tr_keys)
  end

  it 'declares crawler boundaries and the canonical sitemap' do
    robots = Rails.public_path.join('robots.txt').read

    expect(robots).to include("Disallow: /app\n")
    expect(robots).to include("Disallow: /api\n")
    expect(robots).to include("Disallow: /widget\n")
    expect(robots).to include('Sitemap: https://www.kozmopath.com/sitemap.xml')
  end
end
