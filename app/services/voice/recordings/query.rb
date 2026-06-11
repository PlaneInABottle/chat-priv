class Voice::Recordings::Query
  def initialize(account:, params:, inbox_ids: nil)
    @account = account
    @params = params || {}
    @inbox_ids = inbox_ids
  end

  def results
    scope = account.voice_recordings.includes(call: [:contact, :inbox]).latest_first
    scope = filter_by_allowed_inboxes(scope)
    scope = filter_by_status(scope)
    scope = filter_by_inbox(scope)
    scope = filter_by_contact(scope)
    scope = filter_by_phone(scope)
    scope = filter_by_call_status(scope)
    scope = filter_by_handoff_status(scope)
    scope = filter_by_date_range(scope)
    scope.limit(limit)
  end

  private

  attr_reader :account, :params, :inbox_ids

  def filter_by_allowed_inboxes(scope)
    return scope if inbox_ids.nil?

    scope.joins(:call).where(calls: { inbox_id: inbox_ids })
  end

  def filter_by_status(scope)
    return scope if params[:status].blank?

    scope.where(status: params[:status])
  end

  def filter_by_inbox(scope)
    return scope if params[:inbox_id].blank?

    scope.joins(:call).where(calls: { inbox_id: params[:inbox_id] })
  end

  def filter_by_contact(scope)
    return scope if params[:contact_id].blank?

    scope.joins(:call).where(calls: { contact_id: params[:contact_id] })
  end

  def filter_by_phone(scope)
    return scope if params[:phone].blank?

    scope.joins(call: :contact).where('contacts.phone_number ILIKE ?', "%#{sanitize_like(params[:phone])}%")
  end

  def filter_by_call_status(scope)
    return scope if params[:call_status].blank?

    scope.joins(:call).where(calls: { status: params[:call_status] })
  end

  def filter_by_handoff_status(scope)
    return scope if params[:handoff_status].blank?

    scope.joins(:call).where("calls.meta->>'handoff_status' = ?", params[:handoff_status])
  end

  def filter_by_date_range(scope)
    scope = scope.where('voice_recordings.created_at >= ?', Time.zone.parse(params[:from])) if params[:from].present?
    scope = scope.where('voice_recordings.created_at <= ?', Time.zone.parse(params[:to])) if params[:to].present?
    scope
  rescue ArgumentError
    scope
  end

  def sanitize_like(value)
    ActiveRecord::Base.sanitize_sql_like(value.to_s)
  end

  def limit
    params.fetch(:limit, 25).to_i.clamp(1, 100)
  end
end
