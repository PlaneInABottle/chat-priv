class Api::V1::Accounts::Conversations::LabelsController < Api::V1::Accounts::Conversations::BaseController
  include LabelConcern

  before_action :validate_labels_exist_for_bot, only: [:create], if: :bot_request?

  private

  def model
    @model ||= @conversation
  end

  def permitted_params
    params.permit(:conversation_id, labels: [])
  end

  def bot_request?
    Current.user.is_a?(AgentBot)
  end

  def validate_labels_exist_for_bot
    return if permitted_params[:labels].blank?

    # Defensive: compact to handle any nil values in the array
    requested_labels = permitted_params[:labels].compact
    existing_labels = Current.account.labels.where('LOWER(title) IN (?)', requested_labels.map(&:downcase)).pluck(:title)
    labels_by_downcased_title = existing_labels.index_by(&:downcase)
    invalid_labels = requested_labels.reject { |label| labels_by_downcased_title.key?(label.downcase) }

    return render_missing_labels(invalid_labels) if invalid_labels.any?

    params[:labels] = requested_labels.map { |label| labels_by_downcased_title[label.downcase] }
  end

  def render_missing_labels(invalid_labels)
    render json: {
      error: 'Labels not found',
      message: "The following labels do not exist: #{invalid_labels.join(', ')}. Bots can only use existing labels."
    }, status: :unprocessable_entity
  end
end
