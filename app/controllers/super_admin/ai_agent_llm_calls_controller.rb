class SuperAdmin::AiAgentLlmCallsController < SuperAdmin::ApplicationController
  LIMIT = 50

  def index
    @llm_calls = llm_calls_scope.includes(:account, :ai_agent, :conversation, :message).reorder(created_at: :desc).limit(LIMIT)
    @account_options = Account.order(:name).pluck(:id, :name)
    @step_options = AiAgentLlmCall.distinct.order(:step).pluck(:step)

    respond_to do |format|
      format.html
      format.json { render json: { payload: @llm_calls.map { |llm_call| serialized_call(llm_call) } } }
    end
  end

  private

  def llm_calls_scope
    scope = AiAgentLlmCall.left_joins(:account)
    scope = scope.where(account_id: params[:account_id].to_i) if params[:account_id].present?
    scope = scope.where(conversation_id: params[:conversation_id].to_i) if params[:conversation_id].present?
    if params[:conversation_display_id].present?
      scope = scope.joins(:conversation).where(conversations: { display_id: params[:conversation_display_id].to_i })
    end
    scope = scope.where(status: params[:status]) if params[:status].present? && AiAgentLlmCall.statuses.key?(params[:status])
    scope = scope.where(step: params[:step]) if params[:step].present?
    scope
  end

  # rubocop:disable Metrics/MethodLength
  def serialized_call(llm_call)
    {
      id: llm_call.id,
      account_id: llm_call.account_id,
      account_name: llm_call.account&.name,
      ai_agent_id: llm_call.ai_agent_id,
      ai_agent_name: llm_call.ai_agent&.name,
      conversation_id: llm_call.conversation_id,
      conversation_display_id: llm_call.conversation&.display_id,
      conversation_url: conversation_url(llm_call),
      message_id: llm_call.message_id,
      model: llm_call.model,
      step: llm_call.step,
      mode: llm_call.mode,
      status: llm_call.status,
      request_messages: llm_call.request_messages,
      request_tool_names: llm_call.request_tool_names,
      response: llm_call.response,
      usage: llm_call.usage,
      finish_reason: llm_call.finish_reason,
      error_code: llm_call.error_code,
      error_message: llm_call.error_message,
      duration_ms: llm_call.duration_ms,
      created_at: llm_call.created_at
    }
  end
  # rubocop:enable Metrics/MethodLength

  def conversation_url(llm_call)
    return unless llm_call.conversation

    "/app/accounts/#{llm_call.account_id}/conversations/#{llm_call.conversation.display_id}"
  end
end
