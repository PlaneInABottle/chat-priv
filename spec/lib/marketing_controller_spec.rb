require 'rails_helper'

RSpec.describe MarketingController do
  contract_files = {
    'public/marketing/assets/pexels-2529148-gray-neon-sneakers.jpg' =>
      '0056824a2f5c095110a822f2a1f4aaad0a37ac647f5c6603e2768b515cf0b58c',
    'public/marketing/assets/ikas-official-wordmark.svg' =>
      '791cfbaa104fe90a9d11f57f8c7872be9b41fafd1a9a9aad0592e64fa2206ffc',
    'public/brand-assets/logo.svg' => '3542ae59bc8a922d7d51a31304d38e6bc360864ab7d8bdcf29a8d3ca7443d3af',
    'public/brand-assets/logo_dark.svg' => '6e54b2f47d8a8329554f1261c360ea622a4e557d55569d09d86926a6427725dc',
    'public/brand-assets/logo_thumbnail.svg' => '38a437c237431bdfc9a3e4e3cfa36c287aa2099a5cb5303b0b0985ab5a449f40'
  }

  it 'preserves the approved stylesheet and visual asset bytes' do
    contract_files.each do |relative_path, expected_sha|
      path = Rails.root.join(relative_path)

      expect(path).to exist
      expect(Digest::SHA256.file(path).hexdigest).to eq(expected_sha)
    end
  end

  it 'includes the selected Variant A conversion layer without the guided rail' do
    stylesheet = Rails.root.join('app/javascript/entrypoints/marketing.scss').read

    expect(stylesheet).to include('.marketing-home.variant-a .hero-freemium-truth')
    expect(stylesheet).to include('.marketing-home.variant-a .final-freemium-button')
    expect(stylesheet).not_to include('.trial-runway', '.guided-trial')
    expect(stylesheet).not_to match(/\.trial-|\[data-trial-/)
  end

  it 'keeps explicit reduced-motion and mobile recomposition rules' do
    stylesheet = Rails.root.join('app/javascript/entrypoints/marketing.scss').read

    expect(stylesheet).to include('@media (max-width: 800px)')
    expect(stylesheet).to include('@media (prefers-reduced-motion: reduce)')
    expect(stylesheet).to include('.control-grid article { min-height: 156px;')
    expect(stylesheet).to include('.text-link { display: none; }')
    expect(stylesheet).to include('.catalog-answer-router { margin: 0; grid-template-columns: 1fr;')
    expect(stylesheet).to include('.handoff-dossier-field { grid-template-columns: 1fr;')
  end

  def css_rules(stylesheet)
    stylesheet.scan(/(?<selectors>[^{}]+)\{(?<declarations>[^{}]+)\}/).map do |selectors, declarations|
      [selectors.split(',').map(&:strip), declarations]
    end
  end

  def css_color_tokens(stylesheet)
    root = css_rules(stylesheet).find { |selectors, _declarations| selectors.include?(':root') }&.last.to_s
    root.scan(/--([a-z0-9-]+):\s*(#[0-9a-f]{6})/i).to_h
  end

  def resolve_css_color(value, tokens)
    color = if value.include?('var(--')
              tokens[value[/--[a-z0-9-]+/]&.delete_prefix('--')]
            else
              value
            end
    color if color&.match?(/\A#[0-9a-f]{6}\z/i)
  end

  def linearize_channel(channel)
    value = channel / 255.0
    value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
  end

  def color_luminance(hex)
    red, green, blue = hex.delete_prefix('#').scan(/../).map { |part| linearize_channel(part.to_i(16)) }
    (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
  end

  def contrast_ratio(foreground, background)
    lighter, darker = [color_luminance(foreground), color_luminance(background)].sort.reverse
    (lighter + 0.05) / (darker + 0.05)
  end

  it 'keeps normal-size marketing text at WCAG AA contrast' do
    stylesheet = Rails.root.join('app/javascript/entrypoints/marketing.scss').read
    rules = css_rules(stylesheet)
    tokens = css_color_tokens(stylesheet)
    contrast_pairs = [
      ['.contact-copy small', '#fffdf7'],
      ['.flow-strip span', '#fffdf7'],
      ['.section-index', '#f6cdbf'],
      ['.section-copy > p:not(.section-index)', '#f6cdbf'],
      ['.reasoning-steps small', '#fffdf7'],
      ['.board-foot span', '#f4f2eb'],
      ['.anatomy-kicker', '#f0ede4'],
      ['.anatomy-fields > p', '#f0ede4'],
      ['.presentation-modes li small', '#f0ede4'],
      ['.channel-proof-note', '#dfe4ff'],
      ['.router-product small', '#ffffff'],
      ['.router-core li', '#10211f'],
      ['.router-rich-output > p', '#fffdf7'],
      ['.router-compact-output p', '#fffdf7'],
      ['.handoff-event small', '#f4f2eb'],
      ['.handoff-composer', '#fffdf7'],
      ['.dossier-continuity p', '#f6cdbf'],
      ['.control-grid p', '#10211f'],
      ['.control-console-note', '#10211f'],
      ['.legal-section p', '#f3f0e8'],
      ['.legal-section a', '#f3f0e8'],
      ['.legal-updated', '#f3f0e8']
    ]
    failures = contrast_pairs.filter_map do |selector, background, inherited_selector|
      color_selectors = [selector, inherited_selector].compact
      rule = color_selectors.filter_map do |color_selector|
        rules.find { |selectors, declarations| selectors.include?(color_selector) && declarations.match?(/color:\s*[^;]+/i) }
      end.first
      foreground_value = rule&.last&.match(/color:\s*([^;]+)/i)&.[](1)&.strip
      foreground = resolve_css_color(foreground_value, tokens) if foreground_value
      ratio = contrast_ratio(foreground, background) if foreground

      "#{selector}: #{foreground || 'missing color'} on #{background} = #{ratio&.round(4) || 'unmeasured'}" if ratio.nil? || ratio < 4.5
    end

    expect(failures).to be_empty, failures.join("\n")
  end

  it 'keeps hero panels free of backdrop-filter' do
    stylesheet = Rails.root.join('app/javascript/entrypoints/marketing.scss').read
    rules = stylesheet.scan(/(?<selectors>[^{}]+)\{(?<declarations>[^{}]+)\}/).map do |selectors, declarations|
      [selectors.split(',').map(&:strip), declarations]
    end
    declarations_for = lambda do |selector|
      rules.find { |selectors, _declarations| selectors.include?(selector) }&.last
    end

    product_proof = declarations_for.call('.product-proof')
    flow_strip = declarations_for.call('.flow-strip')

    expect(product_proof).not_to be_nil
    expect(flow_strip).not_to be_nil
    expect(product_proof).not_to include('backdrop-filter')
    expect(flow_strip).not_to include('backdrop-filter')
    expect(product_proof).to include('background: var(--paper-strong);')
    expect(flow_strip).to include('background: var(--paper-strong);')
  end

  it 'keeps the below-fold figcaption blur intact' do
    stylesheet = Rails.root.join('app/javascript/entrypoints/marketing.scss').read
    rules = stylesheet.scan(/(?<selectors>[^{}]+)\{(?<declarations>[^{}]+)\}/).map do |selectors, declarations|
      [selectors.split(',').map(&:strip), declarations]
    end
    declarations_for = lambda do |selector|
      rules.find { |selectors, _declarations| selectors.include?(selector) }&.last
    end

    figcaption = declarations_for.call('.anatomy-media figcaption')

    expect(figcaption).not_to be_nil
    expect(figcaption).to include('backdrop-filter: blur(10px);')
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

  it 'keeps the exact freemium English source strings' do
    expect(I18n.t('marketing.freemium.announcement', locale: :en)).to eq('50 AI conversations every month.')
    expect(I18n.t('marketing.freemium.start_note', locale: :en)).to eq('600 AI credits per month.')
  end

  it 'adds the legal page styles without touching the trial-free guard' do
    stylesheet = Rails.root.join('app/javascript/entrypoints/marketing.scss').read
    mobile_blocks = stylesheet.scan(/@media \(max-width: 800px\) \{(.*?)\n\}/m)

    expect(stylesheet).to include('.legal-page {')
    expect(stylesheet).to include('.legal-shell {')
    expect(stylesheet).to include('.legal-section {')
    expect(stylesheet).to include('.legal-page a:focus-visible { outline: 3px solid')
    expect(mobile_blocks.flatten.join).to include('.legal-shell { width: calc(100% - 40px);')
    expect(stylesheet).not_to match(/\.trial-|\[data-trial-/)
  end

  it 'keeps signup legal-link configuration and source parity' do
    config = YAML.load_file(Rails.root.join('config/installation_config.yml'))
    urls = config.filter_map { |entry| [entry['name'], entry['value']] if entry['value'] }.to_h

    expect(urls.fetch('TERMS_URL')).to eq(MarketingController::LEGAL_PAGE_URLS.fetch(:terms_of_service))
    expect(urls.fetch('PRIVACY_URL')).to eq(MarketingController::LEGAL_PAGE_URLS.fetch(:privacy_policy))

    %w[en tr].each do |locale|
      signup = JSON.parse(Rails.root.join("app/javascript/dashboard/i18n/locale/#{locale}/signup.json").read)
      terms_accept = signup.dig('REGISTER', 'TERMS_ACCEPT')

      expect(terms_accept).to include(MarketingController::LEGAL_PAGE_URLS.fetch(:terms_of_service))
      expect(terms_accept).to include(MarketingController::LEGAL_PAGE_URLS.fetch(:privacy_policy))
    end
  end

  it 'declares crawler boundaries and the canonical sitemap' do
    robots = Rails.public_path.join('robots.txt').read

    expect(robots).to include("Disallow: /app\n")
    expect(robots).to include("Disallow: /api\n")
    expect(robots).to include("Disallow: /widget\n")
    expect(robots).to include('Sitemap: https://www.kozmopath.com/sitemap.xml')
  end
end
