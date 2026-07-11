class Api::V1::Accounts::AiImprovementUsageController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_admin_authorization?

  def show
    render json: AiImprovements::Usage::Summary.new(account: Current.account).payload
  end
end
