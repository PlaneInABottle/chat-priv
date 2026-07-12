require 'rails_helper'

RSpec.describe AiAgents::EvaluationTextSanitizer do
  it 'replaces internal tool identifiers with customer-facing behavior' do
    text = 'Asistan, human_handoff aracını kullanır, search_knowledge ile kontrol eder ve müşteriyi bilgilendirir.'

    expect(described_class.sanitize(text)).to eq(
      'Asistan, konuşmayı bir temsilciye aktarır, verified business information ile kontrol eder ve müşteriyi bilgilendirir.'
    )
  end
end
