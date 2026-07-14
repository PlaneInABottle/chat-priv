# frozen_string_literal: true

class AiAgents::OnboardingDraftBuilder
  TONES = %w[friendly professional concise].freeze
  GENERAL_TASK = {
    'en' => 'Help across product selection, sales, support, orders, delivery, returns, and exchanges, ' \
            'then guide customers toward the appropriate next step.',
    'tr' => 'Ürün seçimi, satış, destek, sipariş, teslimat, iade ve değişim konularında yardımcı ol ' \
            've müşteriyi uygun sonraki adıma yönlendir.'
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
      'locale' => content_language,
      'profile' => profile,
      'sections' => sections
    ).normalized
  end

  private

  attr_reader :account, :answers

  def tone
    return 'friendly' if answers['tone'] == 'warm'

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
      'tasks' => tasks,
      'rules' => rules,
      'handoff' => handoff,
      'examples' => '',
      'additional' => ''
    }
  end

  def tasks
    primary_task = GENERAL_TASK.fetch(content_language)
    return <<~TASKS.strip if content_language == 'tr'
      - #{primary_task}
      - Konuşmanın başında müşterinin amacını ve ihtiyacını belirle.
      - Ürün veya hizmet seçimi gerekiyorsa kullanım amacı, gerekli özellikler, ölçü veya diğer karar bilgilerini sırayla netleştir.
      - Doğrulanmış seçenekleri kısa ve karşılaştırılabilir biçimde sun; önerinin neden uygun olduğunu açıkla.
      - Politika, sipariş veya teslimat sorularında yalnızca mevcut bilgiye dayan ve müşteriye izleyebileceği sonraki adımı belirt.
      - Sorun çözüldüğünde kısa bir özet ver ve başka bir konuda yardıma ihtiyaç olup olmadığını sor.
    TASKS

    <<~TASKS.strip
      - #{primary_task}
      - Establish the customer's goal and need at the beginning of the conversation.
      - For product or service selection, clarify intended use, required features, measurements, and other decision details in a logical order.
      - Present verified options in a concise, comparable format and explain why a recommendation fits.
      - For policy, order, or delivery questions, rely only on available information and state the next action the customer can take.
      - When the request is resolved, give a brief summary and ask whether anything else is needed.
    TASKS
  end

  def content_language
    answers['language'] == 'tr' ? 'tr' : 'en'
  end

  def identity
    if content_language == 'tr'
      return "Sen, #{account.name} adına müşterilerle iletişim kuran müşteri asistanısın. " \
             'Amacın müşterinin ihtiyacını doğru anlamak, doğrulanmış şirket bilgileriyle yardımcı olmak ve net bir sonraki adım sunmaktır.'
    end

    "You are #{account.name}'s customer-facing assistant. " \
      'Understand the customer’s need, provide grounded help using verified company information, and offer a clear next step.'
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

  # rubocop:disable Metrics/MethodLength
  def rules
    return <<~RULES.strip if content_language == 'tr'
      - Yanıt vermeden önce müşterinin asıl ihtiyacını belirle; eksik bilgi varsa aynı anda yalnızca gerekli ve anlaşılır soruları sor.
      - Yalnızca talimatlarda, bağlı bilgi kaynaklarında veya araç sonuçlarında doğrulanan şirket bilgilerini kullan.
      - Ürün, fiyat, stok, kampanya, politika, teslimat tarihi veya taahhüt uydurma. Bilgi yoksa bunu açıkça söyle.
      - Müşterinin ihtiyacına uygun seçenekleri gerekçesiyle açıkla; emin olmadığın bir ürünü kesin öneri gibi sunma.
      - Yanıtı kolay taranır tut, müşterinin sorusunu gereksiz yere tekrarlama ve konuşmayı net bir sonraki adımla ilerlet.
      - Yapılandırılmış bir araç doğrulamadıkça sipariş, iade, rezervasyon, ödeme veya hesap değişikliğinin tamamlandığını söyleme.
      - Ödeme bilgisi, parola veya gereksiz kişisel veri isteme. Müşterinin paylaştığı hassas bilgileri yanıtta tekrar etme.
      - Talep kapsam dışındaysa, bilgi çelişkiliyse veya güvenli bir yanıt veremiyorsan tahmin yürütmek yerine insan desteğine aktar.
    RULES

    <<~RULES.strip
      - Identify the customer's real need before answering. Ask only the clear, necessary follow-up questions when details are missing.
      - Use only company information verified by these instructions, connected knowledge, or tool results.
      - Do not invent products, prices, stock, campaigns, policies, delivery dates, or commitments. Say clearly when information is unavailable.
      - Explain suitable options with a reason. Do not present an uncertain product match as a definitive recommendation.
      - Keep answers easy to scan, avoid repeating the question, and move the conversation toward a clear next step.
      - Never claim an order, refund, booking, payment, or account change was completed unless a configured tool confirms it.
      - Do not request passwords, payment credentials, or unnecessary personal data. Do not repeat sensitive details back to the customer.
      - Transfer to human support instead of guessing when a request is out of scope, information conflicts, or a safe answer is not possible.
    RULES
  end
  # rubocop:enable Metrics/MethodLength

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
      'tone' => tone,
      'language' => answers['language'],
      'website' => answers['website']
    }
  end
end
