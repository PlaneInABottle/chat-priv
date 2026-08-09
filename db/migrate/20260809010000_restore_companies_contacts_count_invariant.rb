# frozen_string_literal: true

class RestoreCompaniesContactsCountInvariant < ActiveRecord::Migration[7.2]
  CHECK_CONSTRAINT = 'companies_contacts_count_not_null'

  def up
    change_column_default :companies, :contacts_count, 0

    add_check_constraint :companies,
                         'contacts_count IS NOT NULL',
                         name: CHECK_CONSTRAINT,
                         validate: false

    execute <<~SQL.squish
      UPDATE companies
      SET contacts_count = 0
      WHERE contacts_count IS NULL
    SQL

    validate_check_constraint :companies, name: CHECK_CONSTRAINT
    change_column_null :companies, :contacts_count, false
    remove_check_constraint :companies, name: CHECK_CONSTRAINT
  end

  def down
    change_column_null :companies, :contacts_count, true
    change_column_default :companies, :contacts_count, nil
  end
end
