# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channel::WebWidget do
  context 'when
  web widget channel' do
    let!(:channel_widget) { create(:channel_widget) }

    it 'pre chat options' do
      expect(channel_widget.pre_chat_form_options['pre_chat_message']).to eq 'Share your queries or comments here.'
      expect(channel_widget.pre_chat_form_options['pre_chat_fields'].length).to eq 3
    end
  end

  describe '#web_widget_script' do
    it 'JSON-escapes the configured frontend URL' do
      malicious_url = 'https://example.test/";</script><script>alert(1)</script>'

      with_modified_env FRONTEND_URL: malicious_url do
        script = create(:channel_widget).web_widget_script

        expect(script).not_to include(malicious_url)
        expect(script).to include('\u003c/script\u003e')
      end
    end
  end
end
