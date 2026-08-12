require 'rails_helper'

RSpec.describe 'Accounts API', type: :request do
  describe 'POST /api/v2/accounts' do
    let(:email) { Faker::Internet.email }

    context 'when posting to accounts with correct parameters' do
      let(:account_builder) { double }
      let(:account) { create(:account) }
      let(:user) { create(:user, email: email, account: account) }

      before do
        allow(AccountBuilder).to receive(:new).and_return(account_builder)
      end

      it 'calls account builder' do
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'true', REQUIRE_EMAIL_CONFIRMATION: 'false' do
          allow(account_builder).to receive(:perform).and_return([user, account])

          params = { email: email, user: nil, locale: nil, password: 'Password1!' }

          post api_v2_accounts_url,
               params: params,
               as: :json

          expect(AccountBuilder).to have_received(:new).with(
            params.except(:password).merge(
              user_password: params[:password], confirmed: true, ensure_valid: true, apply_freemium_limits: true,
              account_name: nil, user_full_name: nil
            )
          )
          expect(account_builder).to have_received(:perform)
          expect(response.headers.keys).to include('access-token', 'token-type', 'client', 'expiry', 'uid')
          expect(response.body).to include('en')
        end
      end

      it 'updates the onboarding step in custom attributes' do
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'true', REQUIRE_EMAIL_CONFIRMATION: 'false' do
          allow(account_builder).to receive(:perform).and_return([user, account])

          params = { email: email, user: nil, locale: nil, password: 'Password1!' }

          post api_v2_accounts_url,
               params: params,
               as: :json

          expect(account.reload.custom_attributes['onboarding_step']).to eq('profile_update')
        end
      end

      it 'calls ChatwootCaptcha' do
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'true', REQUIRE_EMAIL_CONFIRMATION: 'false' do
          captcha = double
          allow(account_builder).to receive(:perform).and_return([user, account])
          allow(ChatwootCaptcha).to receive(:new).and_return(captcha)
          allow(captcha).to receive(:valid?).and_return(true)

          params = { email: email, user: nil, password: 'Password1!', locale: nil, h_captcha_client_response: '123' }

          post api_v2_accounts_url,
               params: params,
               as: :json

          expect(ChatwootCaptcha).to have_received(:new).with('123')
          expect(response.headers.keys).to include('access-token', 'token-type', 'client', 'expiry', 'uid')
          expect(response.body).to include('en')
        end
      end

      it 'renders error response on invalid params' do
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'true', REQUIRE_EMAIL_CONFIRMATION: 'false' do
          allow(account_builder).to receive(:perform).and_return(nil)

          params = { email: nil, user: nil, locale: 'en' }

          post api_v2_accounts_url,
               params: params,
               as: :json

          expect(AccountBuilder).to have_received(:new).with(
            params.merge(user_password: params[:password], confirmed: true, ensure_valid: true,
                         apply_freemium_limits: true, account_name: nil, user_full_name: nil)
          )
          expect(account_builder).to have_received(:perform)
          expect(response).to have_http_status(:forbidden)
          expect(response.body).to eq({ message: I18n.t('errors.signup.failed') }.to_json)
        end
      end
    end

    context 'when ENABLE_ACCOUNT_SIGNUP env variable is set to false' do
      it 'responds 404 on requests' do
        params = { email: email }
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'false' do
          post api_v2_accounts_url,
               params: params,
               as: :json

          expect(response).to have_http_status(:not_found)
        end
      end
    end

    context 'when ENABLE_ACCOUNT_SIGNUP is stored as boolean false' do
      before do
        GlobalConfig.clear_cache
        InstallationConfig.where(name: 'ENABLE_ACCOUNT_SIGNUP').delete_all
        InstallationConfig.create!(name: 'ENABLE_ACCOUNT_SIGNUP', value: false, locked: false)
      end

      after do
        InstallationConfig.where(name: 'ENABLE_ACCOUNT_SIGNUP').delete_all
        GlobalConfig.clear_cache
      end

      it 'responds 404 on requests' do
        params = { email: email, password: 'Password1!' }

        post api_v2_accounts_url,
             params: params,
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when ENABLE_ACCOUNT_SIGNUP env variable is set to api_only' do
      let(:account_builder) { double }
      let(:account) { create(:account) }
      let(:user) { create(:user, email: email, account: account) }

      it 'does not respond 404 on requests' do
        allow(AccountBuilder).to receive(:new).and_return(account_builder)
        allow(account_builder).to receive(:perform).and_return([user, account])

        params = { email: email, user: nil, password: 'Password1!', locale: nil }
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'api_only' do
          post api_v2_accounts_url,
               params: params,
               as: :json

          expect(AccountBuilder).to have_received(:new).with(
            params.except(:password).merge(
              user_password: params[:password], confirmed: false, ensure_valid: true, apply_freemium_limits: true,
              account_name: nil, user_full_name: nil
            )
          )
          expect(response).to have_http_status(:success)
        end
      end
    end

    context 'when the user data is invalid' do
      let(:email) { "Invalid-#{SecureRandom.hex(8)}@example.com" }
      let(:params) do
        {
          account_name: 'Invalid Signup',
          email: email,
          user_full_name: 'Invalid Signup Owner',
          password: 'short'
        }
      end

      it 'rejects invalid data when immediate confirmation is enabled' do
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'true', REQUIRE_EMAIL_CONFIRMATION: 'false' do
          expect do
            post api_v2_accounts_url, params: params, as: :json
          end.not_to have_enqueued_mail(Devise::Mailer, :confirmation_instructions)
        end

        expect(response).to have_http_status(:unprocessable_entity)
        expect(User.from_email(email)).to be_nil
      end

      it 'rejects invalid data when confirmation is required' do
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'true', REQUIRE_EMAIL_CONFIRMATION: 'true' do
          expect do
            post api_v2_accounts_url, params: params, as: :json
          end.not_to have_enqueued_mail(Devise::Mailer, :confirmation_instructions)
        end

        expect(response).to have_http_status(:unprocessable_entity)
        expect(User.from_email(email)).to be_nil
      end
    end

    context 'when email confirmation is disabled' do
      let(:email) { "Signup-#{SecureRandom.hex(8)}@Example.COM" }
      let(:normalized_email) { email.downcase }
      let(:params) do
        {
          account_name: 'Immediate Access',
          email: email,
          user_full_name: 'Immediate Access Owner',
          password: 'Password1!'
        }
      end

      it 'confirms and authenticates the user without sending confirmation mail', :aggregate_failures do
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'true', REQUIRE_EMAIL_CONFIRMATION: 'false' do
          expect do
            post api_v2_accounts_url, params: params, as: :json
          end.not_to have_enqueued_mail(Devise::Mailer, :confirmation_instructions)
        end

        user = User.find_by!(email: normalized_email)
        account = user.accounts.first

        expect(response).to have_http_status(:success)
        expect(response.headers.keys).to include('access-token', 'token-type', 'client', 'expiry', 'uid')
        expect(response.parsed_body.dig('data', 'account_id')).to eq(account.id)
        expect(user).to be_confirmed
        expect(user).to have_attributes(
          email: normalized_email,
          unconfirmed_email: nil,
          confirmation_token: nil,
          confirmation_sent_at: nil
        )
      end
    end

    context 'when email confirmation is required' do
      let(:email) { "signup-#{SecureRandom.hex(8)}@example.com" }

      it 'keeps the user unconfirmed and returns an email-only response without auth headers', :aggregate_failures do
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'true', REQUIRE_EMAIL_CONFIRMATION: 'true' do
          expect do
            post api_v2_accounts_url,
                 params: {
                   account_name: 'Confirmation Required',
                   email: email,
                   user_full_name: 'Confirmation Required Owner',
                   password: 'Password1!'
                 },
                 as: :json
          end.to have_enqueued_mail(Devise::Mailer, :confirmation_instructions)
        end

        expect(response).to have_http_status(:success)
        expect(response.headers.keys).not_to include('access-token', 'token-type', 'client', 'expiry', 'uid')
        expect(response.parsed_body).to eq('email' => email)
        expect(User.find_by!(email: email)).not_to be_confirmed
      end

      it 'defaults to requiring confirmation when the setting is absent' do
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'true', REQUIRE_EMAIL_CONFIRMATION: nil do
          post api_v2_accounts_url,
               params: {
                 account_name: 'Safe Default',
                 email: email,
                 user_full_name: 'Safe Default Owner',
                 password: 'Password1!'
               },
               as: :json
        end

        expect(response).to have_http_status(:success)
        expect(response.headers.keys).not_to include('access-token', 'token-type', 'client', 'expiry', 'uid')
        expect(response.parsed_body).to eq('email' => email)
        expect(User.find_by!(email: email)).not_to be_confirmed
      end

      it 'blocks subsequent sign-in for the unconfirmed user' do
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'true', REQUIRE_EMAIL_CONFIRMATION: 'true' do
          post api_v2_accounts_url,
               params: {
                 account_name: 'Blocked Signin',
                 email: email,
                 user_full_name: 'Blocked Signin Owner',
                 password: 'Password1!'
               },
               as: :json
        end

        post new_user_session_url, params: { email: email, password: 'Password1!' }, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['error_code']).to eq('user_not_confirmed')
      end
    end

    context 'when an unauthenticated user signs up with the real builder' do
      let(:email) { "Signup-#{SecureRandom.hex(8)}@Example.COM" }

      it 'persists the freemium quota settings on the created account', :aggregate_failures do
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'true' do
          post api_v2_accounts_url,
               params: { account_name: 'Freemium Signup', email: email, user_full_name: 'Freemium Signup Owner',
                         password: 'Password1!', locale: nil },
               as: :json
        end

        expect(response).to have_http_status(:success)
        account = User.find_by!(email: email.downcase).accounts.first
        expect(account.settings).to include(
          'ai_agent_conversation_limit' => 50,
          'ai_improvement_monthly_credit_limit' => 600
        )
        expect(account.ai_agent_conversation_limit).to eq(50)
        expect(account.ai_improvement_monthly_credit_limit).to eq(600)
      end
    end
  end
end
