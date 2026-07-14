require 'rails_helper'

RSpec.describe SuperAdmin::FeaturesHelper do
  describe '.plan_details' do
    it 'escapes plan data before rendering markup' do
      allow(ChatwootHub).to receive(:pricing_plan).and_return('<script>alert(1)</script>')
      allow(ChatwootHub).to receive(:pricing_plan_quantity).and_return(1)

      result = described_class.plan_details

      expect(result).to be_html_safe
      expect(result).to include('&lt;script&gt;alert(1)&lt;/script&gt;')
      expect(result).not_to include('<script>')
    end

    it 'escapes the agent quantity on premium plans' do
      allow(ChatwootHub).to receive(:pricing_plan).and_return('premium')
      allow(ChatwootHub).to receive(:pricing_plan_quantity).and_return('<img src=x onerror=alert(1)>')

      result = described_class.plan_details

      expect(result).to include('&lt;img src=x onerror=alert(1)&gt; agents')
      expect(result).not_to include('<img')
    end
  end
end
