require 'rails_helper'

RSpec.describe MarketingController do
  contract_files = {
    'app/javascript/entrypoints/marketing.scss' => 'f4249d2c7868bfd6d12667ec6e9431b0d277dc154abddb503ca63093e7770e1b',
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

  it 'keeps normal-size marketing text at WCAG AA contrast' do
    stylesheet = Rails.root.join('app/javascript/entrypoints/marketing.scss').read
    contrast_pairs = [
      ['.contact-copy small', '#fefcf6'],
      ['.demo-disclosure', '#f1eee6'],
      ['.flow-strip span', '#fcfaf3'],
      ['.section-index', '#f6cdbf'],
      ['.section-copy > p:not(.section-index)', '#f6cdbf'],
      ['.reasoning-steps small', '#fffdf7'],
      ['.board-foot span', '#f4f2eb'],
      ['.capability-list small', '#f0ede4'],
      ['.fixture-label', '#edeae2'],
      ['.catalog-query small', '#e7e9e4'],
      ['.catalog-window-foot', '#f4f2eb'],
      ['.device-head', '#fcfbf8'],
      ['.device-input', '#fcfbf8'],
      ['.phone-top small', '#fffdf7'],
      ['.phone-input', '#fffdf7'],
      ['.phone-input i', '#f0eee7', '.phone-input'],
      ['.handoff-event small', '#f4f2eb'],
      ['.handoff-composer', '#fffbf4']
    ]
    linearize = lambda do |channel|
      value = channel / 255.0
      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
    luminance = lambda do |hex|
      red, green, blue = hex.delete_prefix('#').scan(/../).map { |part| linearize.call(part.to_i(16)) }
      (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    end
    contrast_ratio = lambda do |foreground, background|
      lighter, darker = [luminance.call(foreground), luminance.call(background)].sort.reverse
      (lighter + 0.05) / (darker + 0.05)
    end

    rules = stylesheet.scan(/(?<selectors>[^{}]+)\{(?<declarations>[^{}]+)\}/).map do |selectors, declarations|
      [selectors.split(',').map(&:strip), declarations]
    end
    failures = contrast_pairs.filter_map do |selector, background, inherited_selector|
      color_selectors = [selector, inherited_selector].compact
      rule = color_selectors.filter_map do |color_selector|
        rules.find { |selectors, declarations| selectors.include?(color_selector) && declarations.match?(/color:\s*#[0-9a-f]{6}/i) }
      end.first
      foreground = rule&.last&.match(/color:\s*(#[0-9a-f]{6})/i)&.[](1)
      ratio = contrast_ratio.call(foreground, background) if foreground

      "#{selector}: #{foreground || 'missing color'} on #{background} = #{ratio&.round(4) || 'unmeasured'}" if ratio.nil? || ratio < 4.5
    end

    expect(failures).to be_empty, failures.join("\n")
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
