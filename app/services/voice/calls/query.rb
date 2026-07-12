# frozen_string_literal: true

class Voice::Calls::Query
  def initialize(account:, params:, inbox_ids: nil)
    @account = account
    @params = params || {}
    @inbox_ids = inbox_ids
  end

  def results
    scope = account.calls.livekit
                   .where("COALESCE(meta->>'test_call', 'false') <> 'true'")
                   .includes(:conversation, :inbox)
                   .order(created_at: :desc)
    scope = filter_by_allowed_inboxes(scope)
    scope = filter_by_inbox(scope)
    scope = filter_by_status(scope)
    scope = filter_by_handoff_status(scope)
    scope = filter_by_voice_agent(scope)
    scope = filter_by_phone(scope)
    scope = filter_by_date_range(scope)
    scope.limit(limit)
  end

  private

  attr_reader :account, :params, :inbox_ids

  def filter_by_allowed_inboxes(scope)
    return scope if inbox_ids.nil?

    scope.where(inbox_id: inbox_ids)
  end

  def filter_by_inbox(scope)
    return scope if params[:inbox_id].blank?

    scope.where(inbox_id: params[:inbox_id])
  end

  def filter_by_status(scope)
    return scope if params[:status].blank?

    scope.where(status: params[:status])
  end

  def filter_by_handoff_status(scope)
    return scope if params[:handoff_status].blank?

    scope.where("meta->>'handoff_status' = ?", params[:handoff_status])
  end

  def filter_by_voice_agent(scope)
    return scope if params[:voice_agent_id].blank?

    scope.where("meta->>'voice_agent_id' = ?", params[:voice_agent_id].to_s)
  end

  def filter_by_phone(scope)
    return scope if params[:phone].blank?

    query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:phone].to_s)}%"
    scope.left_joins(:contact).where(
      "contacts.phone_number ILIKE :query OR calls.meta->>'from_number' ILIKE :query OR calls.meta->>'to_number' ILIKE :query",
      query: query
    )
  end

  def filter_by_date_range(scope)
    scope = scope.where('calls.created_at >= ?', Time.zone.parse(params[:from])) if params[:from].present?
    scope = scope.where('calls.created_at <= ?', Time.zone.parse(params[:to])) if params[:to].present?
    scope
  rescue ArgumentError
    scope
  end

  def limit
    params.fetch(:limit, 25).to_i.clamp(1, 100)
  end
end
