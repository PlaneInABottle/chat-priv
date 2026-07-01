require 'rails_helper'

RSpec.describe 'Enterprise Super Admin Application Config API', type: :request do
  let(:super_admin) { create(:super_admin) }

  before do
    allow(ChatwootHub).to receive(:pricing_plan).and_return('premium')
  end

  describe 'GET /super_admin/app_config' do
    let!(:config) { upsert_config('AI_AGENT_RESPONSE_BUFFER_SECONDS', 5) }

    it 'shows the AI response buffer on the ai_agents app_config page' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/app_config?config=ai_agents'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('AI_AGENT_RESPONSE_BUFFER_SECONDS')
      expect(response.body).to include(config.value.to_s)
    end
  end

  describe 'POST /super_admin/app_config' do
    it 'updates the AI response buffer on the ai_agents app_config page' do
      sign_in(super_admin, scope: :super_admin)
      post '/super_admin/app_config?config=ai_agents', params: { app_config: { AI_AGENT_RESPONSE_BUFFER_SECONDS: '8' } }

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(super_admin_settings_path)
      expect(InstallationConfig.find_by(name: 'AI_AGENT_RESPONSE_BUFFER_SECONDS').value).to eq('8')
    end
  end

  def upsert_config(name, value)
    InstallationConfig.where(name: name).first_or_initialize.tap do |config|
      config.value = value
      config.locked = false
      config.save!
    end
  end
end
