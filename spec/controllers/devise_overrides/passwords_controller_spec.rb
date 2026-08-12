require 'rails_helper'

RSpec.describe 'DeviseOverrides::PasswordsController', type: :request do
  describe 'POST /auth/password' do
    let(:email) { 'reset-me@example.com' }

    context 'when the user belongs to an account with a non-default locale' do
      let(:account) { create(:account, locale: 'tr') }

      before { create(:user, email: email, account: account) }

      it 'enqueues the reset mail with the user account locale context and returns 200' do
        expect do
          post '/auth/password', params: { email: email }, as: :json
        end.to have_enqueued_mail(Devise::Mailer, :reset_password_instructions)

        expect(response).to have_http_status(:ok)

        mail_job = enqueued_jobs.last
        expect(mail_job[:job].to_s).to eq('ActionMailer::MailDeliveryJob')
        expect(mail_job[:args].last['params']['account']['_aj_globalid']).to eq(account.to_global_id.to_s)
      end
    end

    context 'when the user has no account' do
      before { create(:user, email: email) }

      it 'enqueues the reset mail without an account context' do
        post '/auth/password', params: { email: email }, as: :json

        expect(response).to have_http_status(:ok)

        mail_job = enqueued_jobs.last
        expect(mail_job[:job].to_s).to eq('ActionMailer::MailDeliveryJob')
        expect(mail_job[:args].last['params']['account']).to be_nil
      end
    end
  end
end
