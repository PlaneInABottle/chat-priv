# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Super Admin account AI agent settings locale parity' do
  it 'keeps every maintained English panel key present in Turkish' do
    en_keys = I18n.t('super_admin.account_ai_agent_settings', locale: :en).keys
    tr_keys = I18n.t('super_admin.account_ai_agent_settings', locale: :tr).keys

    expect(tr_keys).to match_array(en_keys)
  end

  it 'keeps all Turkish panel values translated' do
    tr = I18n.t('super_admin.account_ai_agent_settings', locale: :tr)

    expect(tr.values).to all(be_present)
  end
end
# rubocop:enable RSpec/DescribeClass
