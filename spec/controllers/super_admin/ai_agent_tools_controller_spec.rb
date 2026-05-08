require 'rails_helper'

RSpec.describe 'Super Admin AI Agent Tools', type: :request do
  let(:super_admin) { create(:super_admin) }

  it 'redirects unauthenticated users' do
    get '/super_admin/ai_agent_tools'

    expect(response).to have_http_status(:redirect)
  end

  it 'lists registry tools for super admins' do
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_tools'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('human_handoff', 'ikas_lookup_order')
  end

  it 'shows tool details with schema and read-only source code' do
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_tools/human_handoff'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Input schema', 'Service source', 'class HumanHandoffService')
    expect(response.body).not_to include('<textarea')
  end

  it 'returns not found for unknown tools' do
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_tools/unknown_tool'

    expect(response).to have_http_status(:not_found)
  end

  it 'adds the settings card link' do
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/settings'

    expect(response.body).to include('AI Agent Tools', '/super_admin/ai_agent_tools')
  end

  it 'renders analytics and recent logs with account filters' do
    account = create(:account, name: 'Acme')
    ai_agent = create(:ai_agent, account: account)
    create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, status: :executed)
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_tools', params: { account_id: account.id }

    expect(response.body).to include('Account filter', 'Executed', 'Acme')
  end

  it 'keeps settings navigation open for registry pages' do
    helper_context = Class.new do
      include SuperAdmin::NavigationHelper
      attr_accessor :params
    end.new
    helper_context.params = { controller: 'super_admin/ai_agent_tools' }

    expect(helper_context.settings_open?).to be(true)
  end
end
