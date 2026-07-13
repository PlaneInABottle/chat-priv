class AiAgentLearningSuggestionPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def apply?
    @account_user.administrator?
  end

  def dismiss?
    @account_user.administrator?
  end
end
