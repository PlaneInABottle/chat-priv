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
    # Use case-insensitive comparison to match how labels are actually stored
    existing_labels = Current.account.labels.where('LOWER(title) IN (?)', requested_labels.map(&:downcase)).pluck(:title)
    existing_labels_downcased = existing_labels.map(&:downcase)
    invalid_labels = requested_labels.reject { |label| existing_labels_downcased.include?(label.downcase) }

    return if invalid_labels.empty?

    render json: {
      error: 'Labels not found',
      message: "The following labels do not exist: #{invalid_labels.join(', ')}. Bots can only use existing labels."
    }, status: :unprocessable_entity
  end
end
