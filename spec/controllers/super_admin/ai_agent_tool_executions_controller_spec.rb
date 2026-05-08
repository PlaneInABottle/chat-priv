require 'rails_helper'

RSpec.describe 'Super Admin AI Agent Tool Executions', type: :request do
  let(:super_admin) { create(:super_admin) }

  it 'redirects unauthenticated users' do
    get '/super_admin/ai_agent_tool_executions'

    expect(response).to have_http_status(:redirect)
  end

  it 'renders the Vue page for super admins' do
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_tool_executions'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('AI Agent Tool Executions', 'AiAgentToolExecutionsIndex')
  end

  it 'returns JSON logs across accounts for super admins' do
    account = create(:account, name: 'Acme')
    other_account = create(:account, name: 'Beta')
    first = create(:ai_agent_tool_execution, account: account)
    second = create(:ai_agent_tool_execution, account: other_account)
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_tool_executions.json'

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(first.id, second.id)
    expect(response.parsed_body['payload'].pluck('account_name')).to include('Acme', 'Beta')
  end

  it 'filters JSON logs by account, status, tool, and custom date range' do
    account = create(:account)
    matching = create(:ai_agent_tool_execution, account: account, status: :error, tool_key: 'ikas_lookup_order', created_at: '2026-05-08T12:00:00Z')
    create(:ai_agent_tool_execution, status: :error, tool_key: 'ikas_lookup_order', created_at: '2026-05-08T12:00:00Z')
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_tool_executions.json', params: {
      account_id: account.id,
      status: 'error',
      tool_key: 'ikas_lookup_order',
      date_range: 'custom',
      start_date: '2026-05-08T00:00:00Z',
      end_date: '2026-05-08T23:59:59Z'
    }

    expect(response.parsed_body['payload'].pluck('id')).to eq([matching.id])
  end

  it 'sorts JSON logs by allowlisted account name' do
    beta = create(:account, name: 'Beta')
    acme = create(:account, name: 'Acme')
    beta_execution = create(:ai_agent_tool_execution, account: beta)
    acme_execution = create(:ai_agent_tool_execution, account: acme)
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_tool_executions.json', params: { sort: 'account_name', direction: 'asc' }

    expect(response.parsed_body['payload'].pluck('id')).to eq([acme_execution.id, beta_execution.id])
  end

  it 'returns validation errors for invalid custom dates in JSON requests' do
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_tool_executions.json', params: { date_range: 'custom', start_date: 'bad-date' }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['errors']).to include('start_date is invalid')
  end
end
