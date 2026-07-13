require 'rails_helper'

RSpec.describe 'AI Agent Learning Suggestions API', type: :request do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:ai_agent) { create(:ai_agent, account: account) }

  it 'applies reviewed factual guidance as selected shared knowledge' do
    suggestion = create(
      :ai_agent_learning_suggestion,
      :knowledge_ready,
      account: account,
      ai_agent: ai_agent
    )

    post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/learning_suggestions/#{suggestion.id}/apply",
         params: {
           destination: 'knowledge',
           source_name: 'Delivery policy',
           suggested_instruction: 'Delivery timing depends on the destination.'
         },
         headers: administrator.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      'status' => 'applied',
      'destination' => 'knowledge',
      'source_name' => 'Delivery policy'
    )
    source = account.ai_knowledge_sources.find(response.parsed_body.fetch('ai_knowledge_source_id'))
    expect(source.content).to eq('Delivery timing depends on the destination.')
    expect(ai_agent.reload.knowledge_sources).to include(source)
  end
end
