# frozen_string_literal: true

class AccountBuilder
  include CustomExceptions::Account
  pattr_initialize [:account_name, :email!, :confirmed, :user, :user_full_name, :user_password, :super_admin,
                    :locale, :ensure_valid, { apply_freemium_limits: false }]

  def perform
    if @user.nil?
      validate_email
      validate_user
    end
    ActiveRecord::Base.transaction do
      @account = create_account
      @user = create_and_link_user
    end
    [@user, @account]
  rescue StandardError => e
    Rails.logger.debug e.inspect
    raise e
  end

  private

  def user_full_name
    # the empty string ensures that not-null constraint is not violated
    @user_full_name || ''
  end

  def account_name
    # the empty string ensures that not-null constraint is not violated
    @account_name || ''
  end

  def validate_email
    Account::SignUpEmailValidationService.new(@email).perform
  end

  def validate_user
    if User.from_email(@email)
      raise UserExists.new(email: @email)
    else
      true
    end
  end

  def create_account
    @account = Account.create!(
      name: account_name,
      locale: account_locale,
      custom_attributes: { 'onboarding_step' => 'account_details' },
      settings: account_settings
    )
    Current.account = @account
  end

  def account_settings
    settings = { 'ai_agent_enabled' => true, 'voice_ai_enabled' => false }
    return settings unless apply_freemium_limits

    settings.merge(
      'ai_agent_conversation_limit' => Account::FREEMIUM_AI_AGENT_CONVERSATION_MONTHLY_LIMIT,
      'ai_improvement_monthly_credit_limit' => Account::FREEMIUM_AI_IMPROVEMENT_MONTHLY_CREDIT_LIMIT
    )
  end

  def account_locale
    candidate = (@locale.presence || ENV.fetch('DEFAULT_LOCALE', 'tr')).to_s
    I18n.available_locales.map(&:to_s).include?(candidate) ? candidate : 'tr'
  end

  def create_and_link_user
    if @user.present? || create_user
      link_user_to_account(@user, @account)
      @user
    else
      raise UserErrors.new(errors: @user.errors)
    end
  end

  def link_user_to_account(user, account)
    AccountUser.create!(
      account_id: account.id,
      user_id: user.id,
      role: AccountUser.roles['administrator']
    )
  end

  def create_user
    @user = User.new(email: @email.try(:downcase),
                     password: user_password,
                     password_confirmation: user_password,
                     name: user_full_name)
    @user.type = 'SuperAdmin' if @super_admin
    # ensure_valid: true makes Devise validate the user before persisting the
    # confirmed record; without it, confirm saves with `validate: false` and
    # would skip create-time validations on the follow-up save!. Public signup
    # call sites pass ensure_valid: true; legacy callers (OAuth, onboarding)
    # keep the previous behavior by leaving it unset.
    @user.confirm(ensure_valid: @ensure_valid) if @confirmed
    @user.save!
  end
end
