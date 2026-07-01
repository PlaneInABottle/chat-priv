# frozen_string_literal: true

require 'net/http'

class Voice::CallSummaryGenerator
  MAX_TRANSCRIPT_CHARACTERS = 30_000
  MAX_SUMMARY_CHARACTERS = 1_500

  def self.perform(call:)
    new(call: call).perform
  end

  def initialize(call:)
    @call = call
  end

  def perform
    return if skip?

    summary_text = generate_summary
    return if summary_text.blank?

    call.update!(
      summary: {
        'text' => AiAgents::PrivacyRedactor.redact_text(summary_text).truncate(MAX_SUMMARY_CHARACTERS),
        'generated_at' => Time.zone.now.iso8601(3),
        'source' => 'ai_agent_llm',
        'model' => call.account.ai_agent_model
      }
    )
  rescue StandardError => e
    Rails.logger.warn("voice call summary failed call_id=#{call.id} error=#{e.class.name}: #{e.message}")
    nil
  end

  private

  attr_reader :call

  def skip?
    call.test_call? ||
      call.summary.present? ||
      transcript_text.blank? ||
      AiAgents::Settings.llm_api_key.blank?
  end

  def generate_summary
    uri = URI(AiAgents::Settings.llm_endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = AiAgents::Settings.llm_timeout_seconds

    request = Net::HTTP::Post.new(uri.request_uri, headers)
    request.body = request_body.to_json

    response = http.request(request)
    payload = JSON.parse(response.body)
    payload.dig('choices', 0, 'message', 'content').to_s.strip
  end

  def headers
    {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{AiAgents::Settings.llm_api_key}",
      'HTTP-Referer' => 'https://www.kozmopath.com',
      'X-Title' => 'Kozmopath Voice AI'
    }
  end

  def request_body
    {
      model: call.account.ai_agent_model,
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: transcript_text }
      ],
      temperature: 0.2,
      max_tokens: 400
    }
  end

  def system_prompt
    <<~PROMPT.squish
      Bu tamamlanmış müşteri destek sesli görüşmesini bir insan destek temsilcisi için Türkçe özetle.
      Kısa ve net yaz. Müşterinin talebini, önemli kararları veya taahhütleri, çözülmeyen takip
      konularını ve insan temsilciye aktarım istenip istenmediğini belirt. Gerçek olmayan bilgi ekleme.
      Transkriptte Hintçe, Japonca veya başka bir dil gibi görünen kısa/garip parçalar varsa bunları
      kesin dil değişimi olarak kabul etme; özellikle Türkçe konuşma içinde geçiyorsa olası ASR/STT
      hatası veya yanlış duyum olabilir. Emin değilsen bunu "transkript belirsiz" diye belirt ve
      müşterinin niyetini kesinmiş gibi yazma.
    PROMPT
  end

  def transcript_text
    @transcript_text ||= begin
      text = call.transcript_segments.order(:created_at, :id).map do |segment|
        "#{segment.role}: #{segment.text}"
      end.join("\n")
      AiAgents::PrivacyRedactor.redact_text(text).truncate(MAX_TRANSCRIPT_CHARACTERS)
    end
  end
end
