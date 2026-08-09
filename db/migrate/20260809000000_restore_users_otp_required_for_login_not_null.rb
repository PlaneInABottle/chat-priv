# frozen_string_literal: true

class RestoreUsersOtpRequiredForLoginNotNull < ActiveRecord::Migration[7.2]
  CHECK_CONSTRAINT = 'users_otp_required_for_login_not_null'

  def up
    add_check_constraint :users,
                         'otp_required_for_login IS NOT NULL',
                         name: CHECK_CONSTRAINT,
                         validate: false

    execute <<~SQL.squish
      UPDATE users
      SET otp_required_for_login = FALSE
      WHERE otp_required_for_login IS NULL
    SQL

    validate_check_constraint :users, name: CHECK_CONSTRAINT
    change_column_null :users, :otp_required_for_login, false
    remove_check_constraint :users, name: CHECK_CONSTRAINT
  end

  def down
    change_column_null :users, :otp_required_for_login, true
  end
end
