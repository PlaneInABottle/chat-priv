# frozen_string_literal: true

class AiDataRetention::PurgeAccountJob < ApplicationJob
  queue_as :purgable

  def perform(account_id, kind = nil)
    account = Account.find_by(id: account_id)
    return unless account

    result = AiDataRetention::PurgeService.new(account: account).perform(kind: kind)
    Rails.logger.info("ai data retention completed account_id=#{account.id} result=#{result.to_json}")
  end
end
