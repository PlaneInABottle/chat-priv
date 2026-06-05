require 'rails_helper'

RSpec.describe 'Super Admin Application Config API', type: :request do
  let(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/app_config' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        get '/super_admin/app_config'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated super admin' do
      let!(:config) { upsert_config('FB_APP_ID', 'TESTVALUE') }
      let!(:ai_response_buffer_config) { upsert_config('AI_AGENT_RESPONSE_BUFFER_SECONDS', 5) }
      let!(:global_ai_instructions_config) { upsert_config('AI_AGENT_GLOBAL_INSTRUCTIONS', 'Answer in Turkish by default.') }

      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/app_config?config=facebook'
        expect(response).to have_http_status(:success)
        expect(response.body).to include(config.value)
      end

      it 'shows AI Agent settings on the ai_agents app_config page' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/app_config?config=ai_agents'

        expect(response).to have_http_status(:success)
        expect(response.body).to include('AI_AGENT_GLOBAL_INSTRUCTIONS')
        expect(response.body).to include(global_ai_instructions_config.value)
        expect(response.body).to include('AI_AGENT_RESPONSE_BUFFER_SECONDS')
        expect(response.body).to include(ai_response_buffer_config.value.to_s)
      end

      it 'does not show AI Agent settings on the captain app_config page' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/app_config?config=captain'

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include('AI_AGENT_RESPONSE_BUFFER_SECONDS')
        expect(response.body).not_to include('AI_AGENT_GLOBAL_INSTRUCTIONS')
      end
    end
  end

  describe 'GET /super_admin/settings' do
    it 'shows AI Agent settings and hides Captain settings' do
      sign_in(super_admin, scope: :super_admin)

      get '/super_admin/settings'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('AI Agents', '/super_admin/app_config?config=ai_agents')
      expect(response.body).not_to include('Captain')
      expect(response.body).not_to include('/super_admin/app_config?config=captain')
    end
  end

  describe 'POST /super_admin/app_config' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        post '/super_admin/app_config', params: { app_config: { TESTKEY: 'TESTVALUE' } }
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an aunthenticated super admin' do
      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=facebook', params: { app_config: { FB_APP_ID: 'FB_APP_ID' } }

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(super_admin_settings_path)
        expect(flash[:notice]).to be_present
        expect(flash[:alert]).to be_blank
        expect(flash[:success]).to be_blank

        config = GlobalConfig.get('FB_APP_ID')
        expect(config['FB_APP_ID']).to eq('FB_APP_ID')
      end

      it 'asks admins to restart web and worker processes for runtime config changes' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=captain', params: { app_config: { CAPTAIN_OPEN_AI_ENDPOINT: 'https://api.openai.com' } }

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(super_admin_settings_path)
        expect(flash[:success]).to be_present
        expect(flash[:alert]).to be_blank
        expect(flash[:notice]).to be_blank
      end

      it 'updates AI Agent settings on the ai_agents app_config page' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=ai_agents',
             params: { app_config: { AI_AGENT_RESPONSE_BUFFER_SECONDS: '7', AI_AGENT_GLOBAL_INSTRUCTIONS: 'Be concise.' } }

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(super_admin_settings_path)
        expect(InstallationConfig.find_by(name: 'AI_AGENT_RESPONSE_BUFFER_SECONDS').value).to eq('7')
        expect(InstallationConfig.find_by(name: 'AI_AGENT_GLOBAL_INSTRUCTIONS').value).to eq('Be concise.')
      end
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
