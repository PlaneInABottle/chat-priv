require 'rails_helper'

RSpec.describe Voice::AccountCallFinalizerJob, type: :job do
  it 'delegates to the account call finalizer service' do
    account = create(:account)
    allow(Voice::AccountCallFinalizer).to receive(:perform)

    described_class.perform_now(account)

    expect(Voice::AccountCallFinalizer).to have_received(:perform).with(account: account)
  end
end
