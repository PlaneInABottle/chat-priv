# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Super Admin AI Agent Prompt Preview', type: :request do
  let(:super_admin) { create(:super_admin) }

  it 'redirects unauthenticated users' do
    get '/super_admin/ai_agent_prompt_preview'

    expect(response).to have_http_status(:redirect)
  end

  it 'renders the selector for super admins' do
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_prompt_preview'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('AI Prompt Preview', 'Select an account')
  end

  it 'renders the effective prompt, enabled tools, and integration gates for the selected agent' do
    upsert_config('AI_AGENT_GLOBAL_INSTRUCTIONS', 'Use Turkish for Turkish customer messages.')
    account = create(:account, name: 'Acme', settings: { 'ai_agent_model' => 'openai/gpt-4o-mini' })
    ai_agent = create(
      :ai_agent,
      account: account,
      name: 'Catalog Bot',
      prompt: 'Only answer from product and order tools.',
      enabled: true,
      config: {
        'tools' => {
          'enabled' => %w[ikas_catalog_search ikas_lookup_order]
        }
      }
    )
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_prompt_preview', params: { account_id: account.id, ai_agent_id: ai_agent.id }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Catalog Bot', 'openai/gpt-4o-mini', 'Effective system prompt')
    expect(response.body).to include('ikas_catalog_search', 'ikas_lookup_order', 'Tool policy prompt')
    expect(response.body).to include('Global AI instructions', 'Use Turkish for Turkish customer messages.')
    expect(response.body).to include('Only answer from product and order tools.')
    expect(response.body).to include('Never write ₺, TL, TRY, $, €, or any currency symbol/code unless price.currency is present')
  end

  it 'does not preview an AI agent from another account' do
    account = create(:account, name: 'Acme')
    other_agent = create(:ai_agent, name: 'Other Account Bot', prompt: 'Do not show this prompt.')
    create(:ai_agent, account: account, name: 'Local Bot')
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/ai_agent_prompt_preview', params: { account_id: account.id, ai_agent_id: other_agent.id }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Select an AI agent')
    expect(response.body).not_to include('Do not show this prompt.')
  end

  it 'adds the settings card link' do
    sign_in(super_admin, scope: :super_admin)

    get '/super_admin/settings'

    expect(response.body).to include('AI Prompt Preview', '/super_admin/ai_agent_prompt_preview')
  end

  it 'keeps settings navigation open for prompt preview pages' do
    helper_context = Class.new do
      include SuperAdmin::NavigationHelper
      attr_accessor :params
    end.new
    helper_context.params = { controller: 'super_admin/ai_agent_prompt_previews' }

    expect(helper_context.settings_open?).to be(true)
  end

  def upsert_config(name, value)
    InstallationConfig.where(name: name).first_or_initialize.tap do |config|
      config.value = value
      config.locked = false
      config.save!
    end
  end
end
