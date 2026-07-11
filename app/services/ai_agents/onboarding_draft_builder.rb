# frozen_string_literal: true

class AiAgents::OnboardingDraftBuilder
  PURPOSES = %w[support sales support_and_sales orders].freeze
  TONES = %w[friendly professional warm concise].freeze
  PURPOSE_LABELS = {
    'support' => 'customer support',
    'sales' => 'sales guidance',
    'support_and_sales' => 'customer support and sales guidance',
    'orders' => 'order support'
  }.freeze
  PURPOSE_TASKS = {
    'support' => 'Answer customer questions, explain available help, and guide customers toward the appropriate next step.',
    'sales' => 'Explain products and services, help customers compare suitable options, and guide interested customers toward the next sales step.',
    'support_and_sales' => 'Answer support questions, explain products and services, help customers compare options, ' \
                           'and guide them toward the appropriate next step.',
    'orders' => 'Help with general order, delivery, return, and exchange questions while requesting only the information needed for the next step.'
  }.freeze

  def initialize(account:, answers:)
    @account = account
    @answers = answers.deep_stringify_keys
  end

  def agent_attributes
    document = instruction_document
    {
      name: "#{account.name} Assistant",
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
      'identity' => "You are #{account.name}'s customer-facing #{PURPOSE_LABELS.fetch(purpose)} assistant. " \
                    'Provide grounded help using verified company information.',
      'business_context' => business_context,
      'tasks' => PURPOSE_TASKS.fetch(purpose),
      'rules' => rules,
      'handoff' => 'Transfer the conversation to a human whenever the customer asks for a person, the answer is uncertain, ' \
                   'or the request requires human judgment.',
      'examples' => '',
      'additional' => ''
    }
  end

  def business_context
    details = ["Company: #{account.name}."]
    details << "Industry: #{answers['industry']}." if answers['industry'].present?
    details << "Website: #{answers['website']}." if answers['website'].present?
    details.join("\n")
  end

  def rules
    <<~RULES.strip
      Use only verified company information. Do not invent products, prices, stock, policies, delivery dates, or commitments.
      Clearly acknowledge when information is unavailable and offer human support instead of guessing.
      Never claim that an order, refund, booking, or account change was completed unless a configured tool confirms it.
    RULES
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
