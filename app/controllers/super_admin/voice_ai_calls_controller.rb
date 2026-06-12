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
  end

  private

  def calls_scope
    scope = Call.livekit
    scope = scope.where(account_id: params[:account_id].to_i) if params[:account_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present? && Call::STATUSES.include?(params[:status])
    scope = scope.where("calls.meta ->> 'test_call' = ?", params[:test_call]) if %w[true false].include?(params[:test_call])
    if params[:room].present?
      scope = scope.where(
        "calls.provider_call_id ILIKE :query OR calls.meta ->> 'livekit_room_name' ILIKE :query",
        query: room_query
      )
    end
    scope
  end

  def room_query
    "%#{ActiveRecord::Base.sanitize_sql_like(params[:room].to_s.strip)}%"
  end
end
