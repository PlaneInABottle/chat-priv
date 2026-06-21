class SuperAdmin::VoiceAiCallsController < SuperAdmin::ApplicationController
  LIMIT = 50

  def index
    @calls = calls_scope
             .includes(:account, :inbox, :conversation, :voice_recordings, :voice_tool_events, :transcript_segments)
             .reorder(created_at: :desc)
             .limit(LIMIT)
    @account_options = Account.order(:name).pluck(:id, :name)
  end

  def show
    @call = Call.livekit.includes(:account, :inbox, :conversation, :voice_recordings, :voice_tool_events, :transcript_segments).find(params[:id])
    @tool_events = @call.voice_tool_events.order(:created_at, :id)
    @transcript_segments = @call.transcript_segments.order(:created_at, :id)
    @recordings = @call.voice_recordings.latest_first
    @diagnostics = Voice::Diagnostics::CallBundle.new(call: @call, include_livekit: false, include_system_health: false).payload
  end

  def diagnostics
    call = Call.livekit.find(params[:id])
    raw = ActiveModel::Type::Boolean.new.cast(params[:raw])
    log_raw_diagnostics_access(call) if raw

    render json: Voice::Diagnostics::CallBundle.new(call: call, raw: raw).payload
  end

  private

  def calls_scope
    scope = Call.livekit
    scope = scope.where(account_id: params[:account_id].to_i) if params[:account_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present? && Call::STATUSES.include?(params[:status])
    scope = scope.where("calls.meta ->> 'test_call' = ?", params[:test_call]) if %w[true false].include?(params[:test_call])
    apply_room_filter(scope)
  end

  def apply_room_filter(scope)
    return scope if params[:room].blank?

    scope.where(
      "calls.provider_call_id ILIKE :query OR calls.meta ->> 'livekit_room_name' ILIKE :query",
      query: room_query
    )
  end

  def room_query
    "%#{ActiveRecord::Base.sanitize_sql_like(params[:room].to_s.strip)}%"
  end

  def log_raw_diagnostics_access(call)
    Rails.logger.info(
      "[SuperAdmin] raw voice diagnostics accessed call_id=#{call.id} account_id=#{call.account_id} " \
      "actor_id=#{current_super_admin&.id} actor_email=#{current_super_admin&.email}"
    )
  end
end
