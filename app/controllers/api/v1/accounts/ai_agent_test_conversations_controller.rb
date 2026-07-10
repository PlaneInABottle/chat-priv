class Api::V1::Accounts::AiAgentTestConversationsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :ensure_ai_agent_enabled
  before_action :set_ai_agent
  before_action :set_test_conversation, only: [:show, :destroy, :send_message]

  def index
    @test_conversations = @ai_agent.test_conversations
                                   .where(account_id: Current.account.id)
                                   .order(last_message_at: :desc, created_at: :desc)
  end

  def show; end

  def create
    @test_conversation = @ai_agent.test_conversations.create!(
      account: Current.account,
      messages: [],
      title: 'New Test Conversation'
    )
    render :show
  end

  def destroy
    @test_conversation.destroy!
    head :ok
  end

  def clear_all
    @ai_agent.test_conversations.where(account_id: Current.account.id).destroy_all
    head :ok
  end

  def send_message
    content = params[:content].to_s.strip
    return render json: { error: 'Content is required' }, status: :bad_request if content.blank?
    return render json: { error: 'Message limit reached (200 messages max)' }, status: :unprocessable_entity if @test_conversation.at_message_limit?
    return render json: { error: 'Draft instructions are too long' }, status: :unprocessable_entity if effective_test_prompt.length > 50_000

    @test_conversation.append_message(role: 'user', content: content)
    @test_conversation.update!(title: content.truncate(50)) if @test_conversation.title == 'New Test Conversation'

    generate_and_render_ai_response
  end

  private

  def set_ai_agent
    @ai_agent = Current.account.ai_agents.find(params[:ai_agent_id])
  end

  def set_test_conversation
    @test_conversation = @ai_agent.test_conversations.find(params[:id])
  end

  def generate_and_render_ai_response
    result = AiAgents::Orchestrator.new(
      ai_agent: @ai_agent,
      messages: @test_conversation.messages,
      mode: :test,
      conversation: @test_conversation,
      prompt_override: effective_test_prompt
    ).perform

    if result[:assistant_message]
      append_assistant_message(result[:assistant_message])
      @ai_agent.mark_test_succeeded!(prompt: effective_test_prompt)
      render json: {
        message: @test_conversation.messages.last,
        messages: @test_conversation.messages,
        title: @test_conversation.title,
        tested_draft: draft_instructions_provided?
      }
    else
      render json: { error: 'Failed to generate response' }, status: :unprocessable_entity
    end
  end

  def append_assistant_message(message)
    @test_conversation.append_message(
      role: 'assistant',
      content: message['content'],
      metadata: message.except('id', 'role', 'content', 'created_at')
    )
  end

  def effective_test_prompt
    @effective_test_prompt ||= if draft_instructions_provided?
                                 AiAgents::InstructionDocument.new(draft_instructions_param).compile
                               else
                                 @ai_agent.prompt.to_s
                               end
  end

  def draft_instructions_provided?
    params.key?(:draft_instructions)
  end

  def draft_instructions_param
    params.permit(
      draft_instructions: [
        :version,
        :content,
        { profile: [:language, :tone, :formality, :response_length] },
        { sections: [:key, :title, :content, :critical, :custom] }
      ]
    ).fetch(:draft_instructions, {}).to_h
  end
end
