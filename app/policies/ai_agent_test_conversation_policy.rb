class AiAgentTestConversationPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def clear_all?
    @account_user.administrator?
  end

  def send_message?
    @account_user.administrator?
  end

  class Scope < Scope
    def resolve
      scope.where(account_id: @account.id)
    end
  end
end
