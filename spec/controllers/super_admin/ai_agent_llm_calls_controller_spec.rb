require 'rails_helper'

RSpec.describe 'Super Admin AI Agent LLM Calls', type: :request do
  let(:super_admin) { create(:super_admin) }

  it 'redirects unauthenticated users' do
    get '/super_admin/ai_agent_llm_calls'

    expect(response).to have_http_status(:redirect)
  end

  it 'lists LLM calls with request messages for super admins' do
    account = create(:account, name: 'Acme')
    ai_agent = create(:ai_agent, account: account, name: 'Catalog Agent')
    create(:ai_agent_llm_call,
           account: account,
           ai_agent: ai_agent,
           step: 'initial',
           request_messages: [{ 'role' => 'user', 'content' => 'beyaz olanin linki var mi' }],
           request_tool_names: ['ikas_catalog_search'])
    create(:ai_agent_llm_call,
           account: account,
           ai_agent: ai_agent,
           step: 'tool_follow_up_retry')
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_llm_calls'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('AI LLM Calls', 'Acme', 'beyaz olanin linki var mi', 'ikas_catalog_search')
    expect(response.body).to include('Tool follow up retry')
  end

  it 'filters LLM calls by account' do
    visible_account = create(:account, name: 'Visible')
    hidden_account = create(:account, name: 'Hidden')
    create(:ai_agent_llm_call,
           account: visible_account,
           ai_agent: create(:ai_agent, account: visible_account),
           request_messages: [{ 'role' => 'user', 'content' => 'visible request' }])
    create(:ai_agent_llm_call,
           account: hidden_account,
           ai_agent: create(:ai_agent, account: hidden_account),
           request_messages: [{ 'role' => 'user', 'content' => 'hidden request' }])
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_llm_calls', params: { account_id: visible_account.id }

    expect(response.body).to include('visible request')
    expect(response.body).not_to include('hidden request')
  end

  it 'filters LLM calls by visible conversation display ID' do
    account = create(:account)
    conversation = create(:conversation, account: account)
    ai_agent = create(:ai_agent, account: account)
    create(:ai_agent_llm_call,
           account: account,
           ai_agent: ai_agent,
           conversation: conversation,
           request_messages: [{ 'role' => 'user', 'content' => 'visible conversation request' }])
    create(:ai_agent_llm_call,
           account: account,
           ai_agent: ai_agent,
           request_messages: [{ 'role' => 'user', 'content' => 'unlinked request' }])
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_llm_calls', params: { conversation_display_id: conversation.display_id }

    expect(response.body).to include('visible conversation request')
    expect(response.body).not_to include('unlinked request')
  end

  it 'adds the settings card link' do
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/settings'

    expect(response.body).to include('AI LLM Calls', '/super_admin/ai_agent_llm_calls')
  end

  it 'keeps settings navigation open for LLM call pages' do
    helper_context = Class.new do
      include SuperAdmin::NavigationHelper
      attr_accessor :params
    end.new
    helper_context.params = { controller: 'super_admin/ai_agent_llm_calls' }

    expect(helper_context.settings_open?).to be(true)
  end
end
