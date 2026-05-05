class AiAgentPolicy < ApplicationPolicy
  def show?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def simulate?
    @account_user.administrator?
  end
end
