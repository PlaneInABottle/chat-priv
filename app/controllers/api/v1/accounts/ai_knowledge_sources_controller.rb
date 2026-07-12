class Api::V1::Accounts::AiKnowledgeSourcesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :ensure_ai_knowledge_enabled
  before_action :set_source, only: [:show, :update, :destroy]

  def index
    sources = Current.account.ai_knowledge_sources
                     .select(
                       :id, :account_id, :name, :source_type, :created_at, :updated_at,
                       'LEFT(content, 160) AS content_preview',
                       'char_length(content) AS character_count'
                     )
                     .includes(:assignments)
                     .order(updated_at: :desc, id: :desc)
    render json: sources.map { |source| AiKnowledgeSources::Serializer.new(source).payload }
  end

  def show
    render json: AiKnowledgeSources::Serializer.new(@source, include_content: true).payload
  end

  def create
    source = Current.account.ai_knowledge_sources.new(source_params)
    if source.save
      render json: AiKnowledgeSources::Serializer.new(source, include_content: true).payload, status: :created
    else
      render json: { errors: source.errors }, status: :unprocessable_entity
    end
  end

  def update
    if @source.update(source_params)
      render json: AiKnowledgeSources::Serializer.new(@source, include_content: true).payload
    else
      render json: { errors: @source.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    @source.destroy!
    head :no_content
  end

  private

  def ensure_ai_knowledge_enabled
    return if Current.account.ai_agent_enabled? || Current.account.voice_ai_enabled?

    render json: { error: 'AI assistants are not enabled for this account.' }, status: :forbidden
  end

  def set_source
    @source = Current.account.ai_knowledge_sources.includes(:assignments).find(params[:id])
  end

  def source_params
    params.permit(:name, :content)
  end
end
