require 'rails_helper'

RSpec.describe 'AI agents index scaling', type: :request do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  def count_queries
    count = 0
    subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      next if payload[:name].to_s.in?(%w[SCHEMA TRANSACTION])
      next if payload[:sql].start_with?('BEGIN', 'COMMIT')

      count += 1
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  def create_published_agent(name)
    inbox = create(:inbox, account: account)
    agent = create(:ai_agent, account: account, name: name, prompt: 'Answer politely.')
    AgentBotInbox.create!(agent_bot: agent.agent_bot, inbox: inbox, account: account)
    agent
  end

  # Readiness and release metadata are rendered per assistant, so an unbatched association there
  # silently turns the listing into an N+1.
  it 'does not issue more queries as more assistants are listed' do
    create_published_agent('First')
    get "/api/v1/accounts/#{account.id}/ai_agents", headers: admin.create_new_auth_token

    baseline = count_queries { get "/api/v1/accounts/#{account.id}/ai_agents", headers: admin.create_new_auth_token }

    4.times { |index| create_published_agent("Agent #{index}") }
    with_more_agents = count_queries { get "/api/v1/accounts/#{account.id}/ai_agents", headers: admin.create_new_auth_token }

    expect(response.parsed_body.length).to eq(5)
    expect(with_more_agents).to eq(baseline)
  end
end
