class Integrations::Ikas::ConnectionStatus
  IKAS_APP_ID = 'ikas'.freeze

  def initialize(account:)
    @account = account
  end

  def payload
    {
      state: state,
      hook: primary_hook,
      hooks_exist: hooks.exists?,
      store_host: primary_hook&.reference_id,
      client_id: primary_hook&.settings&.[]('client_id'),
      last_validated_at: primary_hook&.settings&.[]('last_validated_at'),
      last_validation_error_code: last_validation_error_code,
      encryption_available: encryption_available?,
      can_connect: can_connect,
      can_disconnect: hooks.exists?
    }
  end

  private

  attr_reader :account

  def hooks
    @hooks ||= account.hooks.where(app_id: IKAS_APP_ID).order(:id)
  end

  def primary_hook
    @primary_hook ||= hooks.first
  end

  def state
    return 'disabled' unless encryption_available?
    return 'not_connected' if primary_hook.blank?
    return 'reconnect_required' if duplicate_hooks?
    return 'reconnect_required' if malformed_hook?

    primary_hook.settings['validation_state'] == 'reconnect_required' ? 'reconnect_required' : 'connected'
  end

  def last_validation_error_code
    return 'duplicate_hook' if duplicate_hooks?
    return 'malformed_hook' if primary_hook.present? && malformed_hook?

    primary_hook&.settings&.[]('last_validation_error_code')
  end

  def encryption_available?
    Chatwoot.encryption_configured?
  end

  def can_connect
    return false unless encryption_available?
    return false if duplicate_hooks?
    return false if primary_hook.present? && malformed_hook?

    true
  end

  def duplicate_hooks?
    account.hooks.where(app_id: IKAS_APP_ID).count > 1
  end

  def malformed_hook?
    unreadable_or_blank_access_token? || primary_hook.reference_id.blank? || primary_hook.settings['client_id'].blank?
  end

  def unreadable_or_blank_access_token?
    primary_hook.access_token.blank?
  rescue ActiveRecord::Encryption::Errors::Decryption
    true
  end
end
