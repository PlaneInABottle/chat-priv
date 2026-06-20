class Api::V1::Accounts::AiAgentUsageController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  def show
    render json: AiAgents::Usage::Summary.new(account: Current.account, include_recent_events: true).payload
  end

  private

  def check_authorization
    authorize(AiAgent, :index?)
  end
end
