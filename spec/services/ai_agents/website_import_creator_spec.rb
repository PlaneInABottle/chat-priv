require 'rails_helper'

RSpec.describe AiAgents::WebsiteImportCreator do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:ai_agent) { create(:ai_agent, account: account) }

  def create_import(website_url: 'example.com')
    described_class.new(ai_agent: ai_agent, website_url: website_url, requested_by: user).perform
  end

  it 'reuses an unchanged ready preview instead of paying to analyze it again' do
    existing = create(
      :ai_agent_website_import,
      :ready,
      account: account,
      ai_agent: ai_agent,
      requested_by: user,
      base_draft_fingerprint: ai_agent.draft_fingerprint
    )

    expect { expect(create_import).to eq(existing) }.not_to have_enqueued_job(AiAgents::WebsiteImportJob)
  end

  it 'limits repeated analysis attempts during the cooldown' do
    create(:ai_agent_website_import, account: account, ai_agent: ai_agent, requested_by: user, status: :failed, created_at: 5.seconds.ago)

    expect { create_import(website_url: 'another.example.com') }
      .to raise_error(described_class::RateLimited) { |error| expect(error.retry_after).to be_between(1, 30) }
  end

  it 'shares the cooldown across assistants in the same account' do
    other_agent = create(:ai_agent, account: account)
    create(:ai_agent_website_import, account: account, ai_agent: other_agent, requested_by: user, status: :failed, created_at: 5.seconds.ago)

    expect { create_import(website_url: 'another.example.com') }.to raise_error(described_class::RateLimited)
  end

  it 'limits analysis attempts across the account each day' do
    10.times do |index|
      create(
        :ai_agent_website_import,
        account: account,
        ai_agent: ai_agent,
        requested_by: user,
        status: :failed,
        created_at: (2.hours + index.minutes).ago
      )
    end

    expect { create_import(website_url: 'another.example.com') }.to raise_error(described_class::RateLimited)
  end
end
