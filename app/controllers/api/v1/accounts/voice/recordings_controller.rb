class Api::V1::Accounts::Voice::RecordingsController < Api::V1::Accounts::BaseController
  before_action :current_account

  def index
    authorize Current.account, :show?

    recordings = Voice::Recordings::Query.new(
      account: Current.account,
      params: filter_params,
      inbox_ids: authorized_inbox_ids
    ).results
    render json: recordings.map { |recording| serialize(recording) }
  end

  private

  def filter_params
    params.permit(:status, :inbox_id, :contact_id, :phone, :call_status, :handoff_status, :from, :to, :limit)
  end

  def authorized_inbox_ids
    policy_scope(Current.account.inboxes).pluck(:id)
  end

  def serialize(recording)
    call = recording.call
    {
      id: recording.id,
      status: recording.status,
      storage_provider: recording.storage_provider,
      content_type: recording.content_type,
      duration_seconds: recording.duration_seconds,
      started_at: recording.started_at&.iso8601,
      completed_at: recording.completed_at&.iso8601,
      error_message: recording.error_message,
      url: recording.completed? ? Voice::Recordings::StorageConfig.new.signed_url(recording) : nil,
      call: {
        id: call.id,
        provider_call_id: call.provider_call_id,
        status: call.status,
        inbox_id: call.inbox_id,
        contact_id: call.contact_id,
        conversation_id: call.conversation&.display_id,
        from_number: call.from_number,
        to_number: call.to_number,
        handoff_status: call.handoff_status
      }
    }.compact
  end
end
