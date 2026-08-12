# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountBuilder do
  let(:email) { 'user@example.com' }
  let(:user_password) { 'Password123!' }
  let(:account_name) { 'Test Account' }
  let(:user_full_name) { 'Test User' }
  let(:validation_service) { instance_double(Account::SignUpEmailValidationService, perform: true) }
  let(:account_builder) do
    described_class.new(
      account_name: account_name,
      email: email,
      user_full_name: user_full_name,
      user_password: user_password,
      confirmed: true
    )
  end

  # Mock the email validation service
  before do
    allow(Account::SignUpEmailValidationService).to receive(:new).with(email).and_return(validation_service)
  end

  describe '#perform' do
    context 'when valid params are passed' do
      it 'creates a new account with correct name' do
        _user, account = account_builder.perform
        expect(account).to be_an(Account)
        expect(account.name).to eq(account_name)
      end

      it 'creates a new confirmed user with correct details' do
        user, _account = account_builder.perform
        expect(user).to be_a(User)
        expect(user.email).to eq(email)
        expect(user.name).to eq(user_full_name)
        expect(user.confirmed?).to be(true)
      end

      it 'links user to account as administrator' do
        user, account = account_builder.perform
        expect(user.account_users.first.role).to eq('administrator')
        expect(user.accounts.first).to eq(account)
      end

      it 'increments the counts of models' do
        expect do
          account_builder.perform
        end.to change(Account, :count).by(1)
           .and change(User, :count).by(1)
           .and change(AccountUser, :count).by(1)
      end

      it 'initializes the onboarding step to account_details' do
        _user, account = account_builder.perform
        expect(account.custom_attributes['onboarding_step']).to eq('account_details')
      end

      it 'enables Text AI for the new account' do
        _user, account = account_builder.perform
        expect(account).to be_ai_agent_enabled
      end

      it 'explicitly disables Voice AI for the new account' do
        _user, account = account_builder.perform
        expect(account.settings).to include('voice_ai_enabled' => false)
        expect(account).not_to be_voice_ai_enabled
        expect(account.feature_enabled?('channel_voice')).to be(false)
      end

      it 'uses a supplied account locale' do
        _user, account = described_class.new(
          account_name: account_name,
          email: email,
          user_full_name: user_full_name,
          user_password: user_password,
          confirmed: true,
          locale: 'tr'
        ).perform

        expect(account.locale).to eq('tr')
      end
    end

    context 'when apply_freemium_limits is not set' do
      it 'does not write freemium quota settings and keeps default readers' do
        _user, account = account_builder.perform

        expect(account.settings).not_to include('ai_agent_conversation_limit', 'ai_improvement_monthly_credit_limit')
        expect(account.settings).to include('ai_agent_enabled' => true, 'voice_ai_enabled' => false)
        expect(account.ai_agent_conversation_limit).to eq(0)
        expect(account.ai_improvement_monthly_credit_limit).to eq(1000)
      end
    end

    context 'when apply_freemium_limits is true' do
      it 'persists freemium quota settings and readers reflect them' do
        _user, account = described_class.new(
          account_name: account_name,
          email: email,
          user_full_name: user_full_name,
          user_password: user_password,
          confirmed: true,
          apply_freemium_limits: true
        ).perform

        expect(account.settings).to include(
          'ai_agent_enabled' => true,
          'voice_ai_enabled' => false,
          'ai_agent_conversation_limit' => 50,
          'ai_improvement_monthly_credit_limit' => 600
        )
        expect(account.ai_agent_conversation_limit).to eq(50)
        expect(account.ai_improvement_monthly_credit_limit).to eq(600)
      end
    end

    context 'when auto-confirming a mixed-case email' do
      let(:email) { 'MixedCaseUser@Example.COM' }

      it 'normalizes the user before confirming without creating confirmation state', :aggregate_failures do
        normalized_email = email.downcase
        user = nil
        account = nil

        expect do
          user, account = account_builder.perform
        end.not_to have_enqueued_mail(Devise::Mailer, :confirmation_instructions)

        expect(user).to be_confirmed
        expect(user).to have_attributes(
          email: normalized_email,
          uid: normalized_email,
          unconfirmed_email: nil,
          confirmation_token: nil,
          confirmation_sent_at: nil
        )
        expect(User.from_email(normalized_email)).to eq(user)
        expect(account.settings).to include('voice_ai_enabled' => false)
      end
    end

    context 'when a user exists with a differently cased email' do
      let(:email) { 'ExistingUser@Example.COM' }

      before do
        create(:user, email: email.downcase)
      end

      it 'raises the handled user-exists error' do
        expect { account_builder.perform }.to raise_error(CustomExceptions::Account::UserExists)
      end
    end

    context 'when ensure_valid is passed for an auto-confirmed signup' do
      let(:invalid_builder) do
        described_class.new(
          account_name: account_name,
          email: email,
          user_full_name: user_full_name,
          user_password: 'short',
          confirmed: true,
          ensure_valid: true
        )
      end

      it 'rejects invalid user data instead of persisting it', :aggregate_failures do
        expect do
          expect { invalid_builder.perform }.to raise_error(ActiveRecord::RecordInvalid)
        end.to not_change(User, :count)
          .and not_change(Account, :count)
      end
    end

    context 'when ensure_valid is not passed for an auto-confirmed signup' do
      it 'preserves the legacy passwordless creation flow used by OAuth' do
        user, account = described_class.new(
          account_name: account_name,
          email: email,
          user_full_name: user_full_name,
          confirmed: true
        ).perform

        expect(user).to be_persisted
        expect(user).to be_confirmed
        expect(account).to be_an(Account)
      end
    end
  end

  describe 'freemium constants' do
    it 'defines the freemium monthly quota values' do
      expect(Account::FREEMIUM_AI_AGENT_CONVERSATION_MONTHLY_LIMIT).to eq(50)
      expect(Account::FREEMIUM_AI_IMPROVEMENT_MONTHLY_CREDIT_LIMIT).to eq(600)
    end
  end
end
