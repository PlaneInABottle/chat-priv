class AiAgentTestConversationPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator? && record_belongs_to_account?
  end

  def create?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator? && record_belongs_to_account?
  end

  def clear_all?
    @account_user.administrator?
  end

  def send_message?
    @account_user.administrator? && record_belongs_to_account?
  end

  class Scope < Scope
    def resolve
      scope.where(account_id: @account.id)
    end
  end

  private

  def record_belongs_to_account?
    record.account_id == @account.id
  end
end
