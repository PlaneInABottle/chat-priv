class AiAgentEvaluationCasePolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def generate?
    create?
  end

  def generation?
    index?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end
end
