class Api::V1::Accounts::AiAgentTestConversationsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
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

    @test_conversation.append_message(role: 'user', content: content)
    @test_conversation.update!(title: content.truncate(50)) if @test_conversation.title == 'New Test Conversation'

    generate_and_render_ai_response
  end

  private

  def set_ai_agent
    @ai_agent = Current.account.ai_agent || Current.account.create_ai_agent
  end

  def set_test_conversation
    @test_conversation = @ai_agent.test_conversations.find(params[:id])
  end

  def generate_and_render_ai_response
    service = AiAgents::ResponseService.new(
      ai_agent: @ai_agent,
      messages: @test_conversation.messages.map { |m| { role: m['role'], content: m['content'] } }
    )
    response_text = service.perform

    if response_text
      @test_conversation.append_message(role: 'assistant', content: response_text)
      render json: { message: @test_conversation.messages.last, messages: @test_conversation.messages, title: @test_conversation.title }
    else
      render json: { error: 'Failed to generate response' }, status: :unprocessable_entity
    end
  end
end
