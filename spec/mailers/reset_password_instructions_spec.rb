# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Devise::Mailer' do
  describe 'reset password instructions' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:reset_token) { user.send(:set_reset_password_token) }
    let(:mail) { Devise::Mailer.reset_password_instructions(user, reset_token, {}) }
    let(:mail_body) { CGI.unescapeHTML(mail.body.to_s) }

    it 'has the correct header data' do
      expect(mail.to).to contain_exactly(user.email)
      expect(mail.subject).to eq('Reset password instructions')
    end

    it 'renders the English body with the reset link' do
      expect(mail_body).to include("Hello #{user.email}!")
      expect(mail_body).to include('Someone has requested a link to change your password.')
      expect(mail_body).to include('Change my password')
      expect(mail_body).to include("If you didn't request this, please ignore this email.")
      expect(mail_body).to include("Your password won't change until you access the link above and create a new one.")
    end

    it 'sends a reset link with the token' do
      expect(mail.body).to include("app/auth/password/edit?reset_password_token=#{reset_token}")
      expect(mail.body).not_to include('app/auth/confirmation')
    end

    context 'when the account locale is Turkish' do
      let(:tr_account) { create(:account, locale: 'tr') }
      let(:user) { create(:user, account: tr_account) }
      let(:mail) { Devise::Mailer.with(account: tr_account).reset_password_instructions(user, reset_token, {}) }

      it 'renders the Turkish subject, body and action' do
        expect(mail.subject).to eq('Şifre talimatlarını sıfırla')
        expect(mail_body).to include("Merhaba #{user.email}!")
        expect(mail_body).to include('Şifrenizi değiştirmek için bir bağlantı talep edildi.')
        expect(mail_body).to include('Şifremi değiştir')
        expect(mail.body).to include("app/auth/password/edit?reset_password_token=#{reset_token}")
      end
    end
  end
end
