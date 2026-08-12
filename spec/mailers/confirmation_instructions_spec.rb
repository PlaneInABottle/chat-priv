# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Devise::Mailer' do
  describe 'notify' do
    let(:account) { create(:account) }
    let!(:confirmable_user) { create(:user, inviter: inviter_val, account: account) }
    let(:inviter_val) { nil }
    let(:mail) { Devise::Mailer.confirmation_instructions(confirmable_user.reload, nil, {}) }
    let(:mail_body) { CGI.unescapeHTML(mail.body.to_s) }
    let(:brand_name) { GlobalConfig.get('BRAND_NAME')['BRAND_NAME'].presence || 'Kozmopath' }
    let(:mailer_sender_address) { Mail::Address.new(Devise.mailer_sender).address }

    before do
      # to verify the token in email
      confirmable_user.update!(confirmed_at: nil)
      confirmable_user.send(:generate_confirmation_token)
    end

    it 'has the correct header data' do
      expect(mail.reply_to).to contain_exactly(mailer_sender_address)
      expect(mail.to).to contain_exactly(confirmable_user.email)
      expect(mail.subject).to eq('Confirmation Instructions')
    end

    it 'uses the user\'s name' do
      expect(mail.body.to_s).to include("Hi #{CGI.escapeHTML(confirmable_user.name)},")
      expect(mail_body).to include("Hi #{confirmable_user.name},")
    end

    context 'when the user name contains HTML' do
      before do
        confirmable_user.update!(name: 'Sony <script>alert(1)</script>')
      end

      it 'escapes the name in the rendered email body' do
        expect(mail.body.to_s).to include("Hi #{CGI.escapeHTML(confirmable_user.name)},")
        expect(mail.body.to_s).not_to include("Hi #{confirmable_user.name},")
      end
    end

    it 'shows the default confirmation state' do
      expect(mail_body).to include('Confirm your email to get started')
      expect(mail_body).to include("Welcome to #{brand_name}. We just need to verify your email address before you can start using your account.")
      expect(mail_body).to include('Confirm my account')
      expect(mail_body).not_to include('Workspace invitation')
    end

    it 'sends a confirmation link' do
      expect(mail.body).to include("app/auth/confirmation?confirmation_token=#{confirmable_user.confirmation_token}")
      expect(mail.body).not_to include('app/auth/password/edit')
    end

    context 'when there is an inviter' do
      let(:inviter_val) { create(:user, :administrator, skip_confirmation: true, account: account) }

      it 'refers to the inviter and their account' do
        expect(mail_body).to include("You're invited to join #{account.name}")
        expect(mail_body).to include("#{inviter_val.name} invited you to join the #{account.name} workspace on #{brand_name}.")
        expect(mail_body).to include('Accept invitation')
        expect(mail_body).not_to include('Confirm your email to get started')
      end

      it 'sends a password reset link' do
        expect(mail.body).to include('app/auth/password/edit?reset_password_token')
        expect(mail.body).not_to include('app/auth/confirmation')
      end
    end

    context 'when user updates the email' do
      before do
        confirmable_user.update!(email: 'user@example.com')
      end

      it 'sends a confirmation link' do
        confirmation_mail = Devise::Mailer.confirmation_instructions(confirmable_user.reload, nil, {})
        confirmation_body = CGI.unescapeHTML(confirmation_mail.body.to_s)

        expect(confirmation_body).to include('Confirm your new email address')
        expect(confirmation_body).to include('New email')
        expect(confirmation_mail.body).to include('app/auth/confirmation?confirmation_token')
        expect(confirmation_mail.body).not_to include('app/auth/password/edit')
        expect(confirmable_user.unconfirmed_email.blank?).to be false
      end
    end

    context 'when user is confirmed and updates the email' do
      before do
        confirmable_user.confirm
        confirmable_user.update!(email: 'user@example.com')
      end

      it 'sends a confirmation link' do
        confirmation_mail = Devise::Mailer.confirmation_instructions(confirmable_user.reload, nil, {})
        confirmation_body = CGI.unescapeHTML(confirmation_mail.body.to_s)

        expect(confirmation_body).to include('Confirm your new email address')
        expect(confirmation_mail.body).to include('app/auth/confirmation?confirmation_token')
        expect(confirmation_mail.body).not_to include('app/auth/password/edit')
        expect(confirmable_user.unconfirmed_email.blank?).to be false
      end
    end

    context 'when user already confirmed' do
      before do
        confirmable_user.confirm
        confirmable_user.account_users.last.destroy!
      end

      it 'send instructions with the link to login' do
        confirmation_mail = Devise::Mailer.confirmation_instructions(confirmable_user.reload, nil, {})
        confirmation_body = CGI.unescapeHTML(confirmation_mail.body.to_s)

        expect(confirmation_body).to include('Your account is ready')
        expect(confirmation_body).to include('Open my account')
        expect(confirmation_mail.body).to include('/auth/sign_in')
      end
    end

    context 'when the account locale is Turkish' do
      let(:tr_account) { create(:account, locale: 'tr') }
      let(:mail) { Devise::Mailer.with(account: tr_account).confirmation_instructions(confirmable_user.reload, nil, {}) }

      it 'renders the Turkish subject, body and action' do
        expect(mail.subject).to eq('Onay Talimatları')
        expect(mail_body).to include('Merhaba')
        expect(mail_body).to include('Başlamak için e-postanızı onaylayın')
        expect(mail_body).to include('Hesabımı onayla')
      end

      it 'renders the Turkish fallback link and the confirmation link with the token' do
        expect(mail_body).to include('Buton çalışmazsa şu bağlantıyı açın:')
        expect(mail_body).to include('güvenli bağlantı')
        expect(mail.body).to include("app/auth/confirmation?confirmation_token=#{confirmable_user.confirmation_token}")
        expect(mail.body).not_to include('app/auth/password/edit')
      end
    end

    context 'when there is an inviter and the account locale is Turkish' do
      let(:tr_account) { create(:account, locale: 'tr') }
      let(:inviter_val) { create(:user, :administrator, skip_confirmation: true, account: tr_account) }
      let!(:confirmable_user) { create(:user, inviter: inviter_val, account: tr_account) }
      let(:mail) { Devise::Mailer.with(account: tr_account).confirmation_instructions(confirmable_user.reload, nil, {}) }

      it 'renders the Turkish invitation branch' do
        expect(mail_body).to include("#{tr_account.name} çalışma alanına davet edildiniz")
        expect(mail_body).to include("#{inviter_val.name} sizi #{brand_name} üzerindeki #{tr_account.name} çalışma alanına davet etti.")
        expect(mail_body).to include('Daveti kabul et')
        expect(mail_body).to include('Davet eden')
        expect(mail_body).to include('Çalışma alanı')
      end
    end

    context 'when the user has no account' do
      let(:accountless_user) { create(:user, skip_confirmation: false) }
      let(:mail) { Devise::Mailer.confirmation_instructions(accountless_user.reload, nil, {}) }

      before do
        accountless_user.send(:generate_confirmation_token)
      end

      it 'falls back to the default locale without an account context' do
        expect(mail.subject).to eq('Confirmation Instructions')
        expect(mail_body).to include('Confirm your email to get started')
        expect(mail_body).to include('Confirm my account')
      end
    end

    it 'keeps English and Turkish confirmation and reset mailer keys aligned' do
      flatten_keys = lambda do |value, prefix = nil|
        value.each_with_object([]) do |(key, nested_value), keys|
          path = [prefix, key].compact.join('.')
          keys.concat(nested_value.is_a?(Hash) ? flatten_keys.call(nested_value, path) : [path])
        end
      end

      # devise_token_auth ships legacy mailer keys in its own config/locales/en.yml
      # that merge into the English tree (e.g. confirm_link_msg, password_change_link).
      # They are not part of the maintained en/tr sources and are excluded from parity.
      legacy_gem_keys = %w[
        confirm_link_msg confirm_account_link
        request_reset_link_msg password_change_link ignore_mail_msg no_changes_msg
      ]

      %w[confirmation_instructions reset_password_instructions].each do |mailer|
        en_keys = flatten_keys.call(I18n.t("devise.mailer.#{mailer}", locale: :en)) - legacy_gem_keys
        tr_keys = flatten_keys.call(I18n.t("devise.mailer.#{mailer}", locale: :tr))

        expect(en_keys).to match_array(tr_keys)
      end
    end
  end
end
