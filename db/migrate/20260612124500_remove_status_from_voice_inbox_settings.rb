class RemoveStatusFromVoiceInboxSettings < ActiveRecord::Migration[7.1]
  def up
    remove_column :voice_inbox_settings, :status, :string, default: 'test_only', null: false
  end

  def down
    add_column :voice_inbox_settings, :status, :string, default: 'test_only', null: false
  end
end
