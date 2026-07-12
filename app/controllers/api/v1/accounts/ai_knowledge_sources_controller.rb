class Api::V1::Accounts::AiKnowledgeSourcesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :ensure_ai_knowledge_enabled
  before_action :set_source, only: [:show, :update, :destroy, :sync]

  def index
    sources = Current.account.ai_knowledge_sources
                     .select(
                       :id, :account_id, :name, :source_type, :created_at, :updated_at,
                       :website_url, :sync_status, :source_urls, :last_sync_started_at, :last_synced_at, :sync_error,
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
    source = Current.account.ai_knowledge_sources.new(create_params)
    if source.save
      enqueue_website_sync(source) if source.website?
      render json: AiKnowledgeSources::Serializer.new(source, include_content: true).payload, status: :created
    else
      render json: { errors: source.errors }, status: :unprocessable_entity
    end
  end

  def update
    if @source.update(update_params)
      enqueue_website_sync(@source) if @source.website? && @source.saved_change_to_website_url?
      render json: AiKnowledgeSources::Serializer.new(@source, include_content: true).payload
    else
      render json: { errors: @source.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    @source.destroy!
    head :no_content
  end

  def sync
    return render json: { error: 'Only website sources can be synced.' }, status: :unprocessable_entity unless @source.website?
    return render json: { error: 'This source is already syncing.' }, status: :conflict if @source.sync_pending? || @source.sync_syncing?

    enqueue_website_sync(@source)
    render json: AiKnowledgeSources::Serializer.new(@source, include_content: true).payload, status: :accepted
  end

  private

  def ensure_ai_knowledge_enabled
    return if Current.account.ai_agent_enabled? || Current.account.voice_ai_enabled?

    render json: { error: 'AI assistants are not enabled for this account.' }, status: :forbidden
  end

  def set_source
    @source = Current.account.ai_knowledge_sources.includes(:assignments).find(params[:id])
  end

  def create_params
    params.permit(:name, :content, :source_type, :website_url)
  end

  def update_params
    return params.permit(:name, :website_url) if @source.website?

    params.permit(:name, :content)
  end

  def enqueue_website_sync(source)
    source.update_columns( # rubocop:disable Rails/SkipsModelValidations -- queue state must not change the content fingerprint
      sync_status: AiKnowledgeSource.sync_statuses.fetch('pending'),
      sync_error: nil
    )
    AiKnowledgeSources::WebsiteSyncJob.perform_later(source.id)
  end
end
