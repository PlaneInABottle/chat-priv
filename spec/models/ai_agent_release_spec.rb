require 'rails_helper'

RSpec.describe AiAgentRelease do
  it 'requires the release and agent to belong to the same account' do
    release = build(:ai_agent_release, account: create(:account))

    expect(release).not_to be_valid
    expect(release.errors[:account]).to include('must own the AI agent')
  end
end
