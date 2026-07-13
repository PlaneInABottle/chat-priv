# frozen_string_literal: true

class AiAgents::OnboardingDraftBuilder
  PURPOSES = %w[support sales support_and_sales orders].freeze
  TONES = %w[friendly professional warm concise].freeze
  PURPOSE_LABELS = {
    'en' => {
      'support' => 'customer support',
      'sales' => 'sales guidance',
      'support_and_sales' => 'customer support and sales guidance',
      'orders' => 'order support'
    },
    'tr' => {
      'support' => 'müşteri destek',
      'sales' => 'satış danışmanı',
      'support_and_sales' => 'müşteri destek ve satış danışmanı',
      'orders' => 'sipariş destek'
    }
  }.freeze
  PURPOSE_TASKS = {
    'en' => {
      'support' => 'Answer customer questions, explain available help, and guide customers toward the appropriate next step.',
      'sales' => 'Explain products and services, help customers compare suitable options, and guide interested customers toward the next sales step.',
      'support_and_sales' => 'Answer support questions, explain products and services, help customers compare options, ' \
                             'and guide them toward the appropriate next step.',
      'orders' => 'Help with general order, delivery, return, and exchange questions while requesting only the information needed for the next step.'
    },
    'tr' => {
      'support' => 'Müşteri sorularını yanıtla, sunulan desteği açıkla ve müşteriyi uygun sonraki adıma yönlendir.',
      'sales' => 'Ürün ve hizmetleri açıkla, müşterilerin uygun seçenekleri karşılaştırmasına yardımcı ol ' \
                 've ilgilenen müşteriyi sonraki satış adımına yönlendir.',
      'support_and_sales' => 'Destek sorularını yanıtla, ürün ve hizmetleri açıkla, müşterilerin seçenekleri ' \
                             'karşılaştırmasına yardımcı ol ve uygun sonraki adıma yönlendir.',
      'orders' => 'Yalnızca sonraki adım için gereken bilgileri isteyerek genel sipariş, teslimat, iade ve değişim sorularında yardımcı ol.'
    }
  }.freeze

  def initialize(account:, answers:)
    @account = account
    @answers = answers.deep_stringify_keys
  end

  def agent_attributes
    document = instruction_document
    {
      name: content_language == 'tr' ? "#{account.name} Asistanı" : "#{account.name} Assistant",
      prompt: AiAgents::InstructionDocument.new(document).compile,
      config: {
        'instructions' => document,
        'tools' => handoff_tools,
        'setup_profile' => setup_profile
      },
      enabled: false
    }
  end

  def instruction_document
    AiAgents::InstructionDocument.new(
      'version' => AiAgents::InstructionDocument::VERSION,
      'profile' => profile,
      'sections' => sections
    ).normalized
  end

  private

  attr_reader :account, :answers

  def purpose
    PURPOSES.include?(answers['purpose']) ? answers['purpose'] : 'support'
  end

  def tone
    TONES.include?(answers['tone']) ? answers['tone'] : 'friendly'
  end

  def profile
    {
      'language' => %w[tr en].include?(answers['language']) ? answers['language'] : 'same_as_customer',
      'tone' => tone,
      'formality' => 'balanced',
      'response_length' => 'balanced'
    }
  end

  def sections
    {
      'identity' => identity,
      'business_context' => business_context,
      'tasks' => PURPOSE_TASKS.dig(content_language, purpose),
      'rules' => rules,
      'handoff' => handoff,
      'examples' => '',
      'additional' => ''
    }
  end

  def content_language
    answers['language'] == 'tr' ? 'tr' : 'en'
  end

  def identity
    if content_language == 'tr'
      return "Sen, #{account.name} şirketinin müşterilerle iletişim kuran #{PURPOSE_LABELS.dig('tr', purpose)} asistanısın. " \
             'Yalnızca doğrulanmış şirket bilgilerine dayanarak yardımcı ol.'
    end

    "You are #{account.name}'s customer-facing #{PURPOSE_LABELS.dig('en', purpose)} assistant. " \
      'Provide grounded help using verified company information.'
  end

  def business_context
    labels = if content_language == 'tr'
               { company: 'Şirket', industry: 'Sektör', website: 'Web sitesi' }
             else
               { company: 'Company', industry: 'Industry', website: 'Website' }
             end
    details = ["#{labels[:company]}: #{account.name}."]
    details << "#{labels[:industry]}: #{answers['industry']}." if answers['industry'].present?
    details << "#{labels[:website]}: #{answers['website']}." if answers['website'].present?
    details.join("\n")
  end

  def rules
    return <<~RULES.strip if content_language == 'tr'
      Yalnızca doğrulanmış şirket bilgilerini kullan. Ürün, fiyat, stok, politika, teslimat tarihi veya taahhüt uydurma.
      Bilgi mevcut olmadığında bunu açıkça belirt ve tahmin etmek yerine insan desteği teklif et.
      Yapılandırılmış bir araç doğrulamadıkça sipariş, iade, rezervasyon veya hesap değişikliğinin tamamlandığını söyleme.
    RULES

    <<~RULES.strip
      Use only verified company information. Do not invent products, prices, stock, policies, delivery dates, or commitments.
      Clearly acknowledge when information is unavailable and offer human support instead of guessing.
      Never claim that an order, refund, booking, or account change was completed unless a configured tool confirms it.
    RULES
  end

  def handoff
    if content_language == 'tr'
      return 'Müşteri bir insanla görüşmek istediğinde, yanıt belirsiz olduğunda veya talep insan değerlendirmesi ' \
             'gerektirdiğinde konuşmayı bir insana aktar.'
    end

    'Transfer the conversation to a human whenever the customer asks for a person, the answer is uncertain, ' \
      'or the request requires human judgment.'
  end

  def handoff_tools
    {
      'enabled' => [AiAgents::Config::HUMAN_HANDOFF_TOOL],
      AiAgents::Config::HUMAN_HANDOFF_TOOL => { 'allowed_labels' => [] }
    }
  end

  def setup_profile
    {
      'source' => 'account_onboarding',
      'purpose' => purpose,
      'tone' => tone,
      'language' => answers['language'],
      'website' => answers['website']
    }
  end
end
