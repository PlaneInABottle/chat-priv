# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260809000000_restore_users_otp_required_for_login_not_null')

RSpec.describe RestoreUsersOtpRequiredForLoginNotNull do
  let(:connection) { ActiveRecord::Base.connection }
  let!(:user) { create(:user) }

  before do
    connection.change_column_null :users, :otp_required_for_login, true
    # rubocop:disable Rails/SkipsModelValidations
    user.update_column(:otp_required_for_login, nil)
    # rubocop:enable Rails/SkipsModelValidations
  end

  it 'backfills null values and restores the not-null invariant' do
    expect { described_class.new.up }.not_to raise_error

    user.reload
    expect(user.otp_required_for_login).to be(false)
    expect(User.where(otp_required_for_login: nil)).to be_empty
    expect(connection.columns(:users).find { |column| column.name == 'otp_required_for_login' }.null).to be(false)
    expect(connection.check_constraints(:users).map(&:name)).not_to include(described_class::CHECK_CONSTRAINT)
  end

  it 'restores nullable column semantics on rollback' do
    described_class.new.up
    described_class.new.down

    expect(connection.columns(:users).find { |column| column.name == 'otp_required_for_login' }.null).to be(true)
  end
end
