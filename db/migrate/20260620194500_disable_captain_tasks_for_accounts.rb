class DisableCaptainTasksForAccounts < ActiveRecord::Migration[7.0]
  def up
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.disable_features!('captain_tasks') }
    end
  end

  def down
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!('captain_tasks') }
    end
  end
end
