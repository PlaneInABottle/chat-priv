# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260809010000_restore_companies_contacts_count_invariant')

RSpec.describe RestoreCompaniesContactsCountInvariant do
  let(:connection) { ActiveRecord::Base.connection }
  let!(:account) { create(:account) }
  let!(:company_id) do
    connection.select_value(<<~SQL.squish)
      INSERT INTO companies (name, account_id, created_at, updated_at)
      VALUES (#{connection.quote('Migration spec company')}, #{account.id}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING id
    SQL
  end

  before do
    connection.change_column_null :companies, :contacts_count, true
    connection.change_column_default :companies, :contacts_count, nil
    connection.execute("UPDATE companies SET contacts_count = NULL WHERE id = #{company_id}")
  end

  it 'backfills null values and restores the default and not-null invariant' do
    expect { described_class.new.up }.not_to raise_error

    contacts_count = connection.select_value("SELECT contacts_count FROM companies WHERE id = #{company_id}")
    expect(contacts_count).to eq(0)
    expect(connection.select_value('SELECT COUNT(*) FROM companies WHERE contacts_count IS NULL').to_i).to eq(0)
    expect(connection.columns(:companies).find { |column| column.name == 'contacts_count' }.null).to be(false)
    expect(connection.columns(:companies).find { |column| column.name == 'contacts_count' }.default).to eq('0')
    expect(connection.check_constraints(:companies).map(&:name)).not_to include(described_class::CHECK_CONSTRAINT)
  end

  it 'removes the default and restores nullable column semantics on rollback' do
    described_class.new.up
    described_class.new.down

    column = connection.columns(:companies).find { |candidate| candidate.name == 'contacts_count' }
    expect(column.null).to be(true)
    expect(column.default).to be_nil
  end
end
