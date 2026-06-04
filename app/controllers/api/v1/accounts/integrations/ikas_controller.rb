class Api::V1::Accounts::Integrations::IkasController < Api::V1::Accounts::BaseController
  IKAS_APP_ID = 'ikas'.freeze

  before_action :check_admin_authorization?
  before_action :ensure_ikas_feature_enabled
  before_action :load_status

  def show
    render json: response_payload
  end

  def create
    if duplicate_hooks?
      return render json: error_response('duplicate_hook'), status: :unprocessable_entity
    end

    return render json: error_response('malformed_hook'), status: :unprocessable_entity if hook.present?

    return render_encryption_unavailable unless @status_payload[:can_connect]

    result = validator.perform
    return render_validation_error(result) unless result.success?

    connected_hook = Current.account.hooks.create!(create_hook_attributes(result))
    enqueue_catalog_sync(connected_hook)
    @status_payload = fresh_status_payload.merge(hook: connected_hook)

    render json: response_payload, status: :created
  end

  def update
    return render_encryption_unavailable if @status_payload[:state] == 'disabled'
    return render json: error_response('not_connected'), status: :not_found if hook.blank?
    return render json: error_response('duplicate_hook'), status: :unprocessable_entity if duplicate_hooks?

    result = validator.perform
    return render_validation_error(result) unless result.success?

    hook.update!(update_hook_attributes(result))
    enqueue_catalog_sync(hook)
    @status_payload = fresh_status_payload

    render json: response_payload
  end

  def destroy
    return render json: error_response('not_connected'), status: :not_found if hook.blank?

    remove_catalog_snapshots!
    Current.account.hooks.where(app_id: IKAS_APP_ID).destroy_all

    render json: disconnected_payload
  end

  def catalog_sync
    return render json: error_response('not_connected'), status: :not_found if hook.blank?
    return render_encryption_unavailable unless @status_payload[:encryption_available]

    enqueue_catalog_sync(hook)
    render json: response_payload
  end

  private

  def response_payload
    app = ikas_app

    {
      app_id: IKAS_APP_ID,
      id: IKAS_APP_ID,
      enabled: @status_payload[:hooks_exist],
      name: app.name,
      description: app.description,
      logo: app.logo,
      state: @status_payload[:state],
      can_connect: @status_payload[:can_connect],
      can_disconnect: @status_payload[:can_disconnect],
      encryption_available: @status_payload[:encryption_available],
      store_host: @status_payload[:store_host],
      store_url: store_url,
      client_id_masked: masked_client_id,
      last_validated_at: @status_payload[:last_validated_at],
      last_validation_error_code: @status_payload[:last_validation_error_code],
      catalog_sync: catalog_sync_payload,
      status_message: status_message,
      uses_api_version: 'v1'
    }
  end

  def load_status
    @status_payload = status_service.payload
  end

  def ensure_ikas_feature_enabled
    return if Current.account.feature_enabled?('ikas_integration')

    render_not_found_error(I18n.t('errors.ikas.unavailable'))
  end

  def status_service
    @status_service ||= Integrations::Ikas::ConnectionStatus.new(account: Current.account)
  end

  def ikas_app
    @ikas_app ||= Integrations::App.find(id: IKAS_APP_ID)
  end

  def fresh_status_payload
    Integrations::Ikas::ConnectionStatus.new(account: Current.account).payload
  end

  def disconnected_payload
    response_payload.merge(
      enabled: false,
      state: Chatwoot.encryption_configured? ? 'not_connected' : 'disabled',
      can_connect: Chatwoot.encryption_configured?,
      can_disconnect: false,
      store_host: nil,
      store_url: nil,
      client_id_masked: nil,
      last_validated_at: nil,
      last_validation_error_code: nil,
      catalog_sync: catalog_sync_payload(nil),
      status_message: I18n.t("errors.ikas.#{Chatwoot.encryption_configured? ? 'not_connected' : 'disabled'}")
    )
  end

  def hook
    @status_payload[:hook]
  end

  def enqueue_catalog_sync(sync_hook)
    Integrations::Ikas::CatalogSyncJob.perform_later(sync_hook.id)
  end

  def remove_catalog_snapshots!
    Current.account.ikas_catalog_snapshots.where(integrations_hook: Current.account.hooks.where(app_id: IKAS_APP_ID)).find_each do |snapshot|
      Integrations::Ikas::Catalog::SnapshotStore.remove_artifact_for(snapshot)
      snapshot.destroy!
    end
  end

  def catalog_sync_payload(payload_hook = hook)
    return { status: 'not_connected' } if payload_hook.blank?

    latest = payload_hook.ikas_catalog_snapshots.order(created_at: :desc, id: :desc).first
    completed = payload_hook.ikas_catalog_snapshots.latest_completed.first
    counts = completed&.counts || {}

    {
      status: latest&.status || 'not_synced',
      last_synced_at: completed&.completed_at&.iso8601,
      started_at: latest&.started_at&.iso8601,
      completed_at: latest&.completed_at&.iso8601,
      products_count: counts['products'].to_i,
      categories_count: counts['categories'].to_i,
      option_sets_count: counts['product_option_sets'].to_i,
      catalog_items_count: counts['catalog_items'].to_i,
      error_message: latest&.failed? ? latest.error_message : nil
    }
  end

  def duplicate_hooks?
    @status_payload[:last_validation_error_code] == 'duplicate_hook'
  end

  def validator
    @validator ||= Integrations::Ikas::ConnectionValidator.new(
      client_id: ikas_params[:client_id],
      client_secret: ikas_params[:client_secret],
      store_url: ikas_params[:store_url],
      existing_secret: stored_access_token,
      existing_client_id: hook&.settings&.[]('client_id')
    )
  end

  def stored_access_token
    hook&.access_token
  rescue ActiveRecord::Encryption::Errors::Decryption
    nil
  end

  def ikas_params
    @ikas_params ||= params.require(:ikas).permit(:client_id, :client_secret, :store_url)
  end

  def create_hook_attributes(result)
    {
      app_id: IKAS_APP_ID,
      access_token: result.client_secret,
      reference_id: result.store_host,
      status: 'enabled',
      settings: hook_settings(result)
    }
  end

  def update_hook_attributes(result)
    {
      access_token: result.client_secret,
      reference_id: result.store_host,
      status: 'enabled',
      settings: hook_settings(result)
    }
  end

  def hook_settings(result)
    {
      client_id: result.client_id,
      validation_state: 'connected',
      last_validated_at: result.last_validated_at,
      last_validation_error_code: nil
    }
  end

  def render_validation_error(result)
    @status_payload = fresh_status_payload
    render json: error_response(result.error_code, result.error_message), status: :unprocessable_entity
  end

  def render_encryption_unavailable
    @status_payload = fresh_status_payload
    render json: error_response('encryption_unavailable'), status: :unprocessable_entity
  end

  def error_response(error_code, message = nil)
    payload = response_payload

    payload.merge(
      state: payload[:state],
      last_validation_error_code: error_code,
      status_message: message || I18n.t("errors.ikas.#{error_code}", default: error_code.humanize)
    )
  end

  def store_url
    return if @status_payload[:store_host].blank?

    "https://#{@status_payload[:store_host]}"
  end

  def masked_client_id
    client_id = @status_payload[:client_id].to_s
    return if client_id.blank?
    return '••••' if client_id.length <= 4

    "#{client_id.first(4)}••••#{client_id.last(4)}"
  end

  def status_message
    I18n.t("errors.ikas.#{@status_payload[:state]}", default: @status_payload[:state].humanize)
  end
end
