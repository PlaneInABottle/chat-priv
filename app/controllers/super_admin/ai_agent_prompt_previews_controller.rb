# frozen_string_literal: true

class SuperAdmin::AiAgentPromptPreviewsController < SuperAdmin::ApplicationController
  def show
    @account_options = Account.order(:name).pluck(:name, :id)
    @account = selected_account
    @ai_agent_options = selected_account_ai_agents.map { |ai_agent| [ai_agent.name, ai_agent.id] }
    @ai_agent = selected_ai_agent
    @preview = AiAgents::EffectivePromptPreview.new(ai_agent: @ai_agent) if @ai_agent.present?
  end

  private

  def selected_account
    return if params[:account_id].blank?

    Account.find_by(id: params[:account_id])
  end

  def selected_account_ai_agents
    @selected_account_ai_agents ||= @account&.ai_agents&.order(:name, :id).to_a || []
  end

  def selected_ai_agent
    return if @account.blank?
    return selected_account_ai_agents.first if params[:ai_agent_id].blank? && selected_account_ai_agents.one?

    selected_account_ai_agents.find { |ai_agent| ai_agent.id == params[:ai_agent_id].to_i }
  end
end
