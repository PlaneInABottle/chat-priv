require 'rails_helper'

RSpec.describe 'Conversation Label API', type: :request do
  let(:account) { create(:account) }

  describe 'GET /api/v1/accounts/{account.id}/conversations/<id>/labels' do
    let(:conversation) { create(:conversation, account: account) }

    before do
      conversation.update_labels('label1, label2')
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id)
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to the conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'returns all the labels for the conversation' do
        get api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include('label1')
        expect(response.body).to include('label2')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/<id>/labels' do
    let(:conversation) { create(:conversation, account: account) }

    before do
      conversation.update_labels('label1, label2')
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
             params: { labels: %w[label3 label4] },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to the conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        conversation.update_labels('label1, label2')
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'creates labels for the conversation' do
        post api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
             params: { labels: %w[label3 label4] },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include('label3')
        expect(response.body).to include('label4')
      end
    end

    context 'when it is an authenticated bot without access to the inbox' do
      let(:agent_bot) { create(:agent_bot) } # Bot without account association

      it 'returns unauthorized' do
        post api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
             params: { labels: %w[existing-label] },
             headers: { api_access_token: agent_bot.access_token.token },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent bot with access token' do
      let(:agent_bot) { create(:agent_bot, account: account) }

      before do
        create(:agent_bot_inbox, agent_bot: agent_bot, inbox: conversation.inbox)
        account.labels.create!(title: 'existing-label')
      end

      it 'allows setting existing labels' do
        post api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
             params: { labels: %w[existing-label] },
             headers: { api_access_token: agent_bot.access_token.token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.label_list).to include('existing-label')
      end

      it 'rejects non-existing labels' do
        post api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
             params: { labels: %w[non-existing-label] },
             headers: { api_access_token: agent_bot.access_token.token },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Labels not found')
      end

      it 'rejects mixed existing and non-existing labels' do
        post api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
             params: { labels: %w[existing-label non-existing-label] },
             headers: { api_access_token: agent_bot.access_token.token },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to include('non-existing-label')
      end
    end

    context 'when it is an authenticated bot with access to the inbox' do
      let(:agent_bot) { create(:agent_bot, account: account) }

      before do
        create(:agent_bot_inbox, inbox: conversation.inbox, agent_bot: agent_bot)
      end

      it 'sets existing labels on the conversation' do
        existing_label = create(:label, account: account, title: 'existing_label')

        post api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
             headers: { api_access_token: agent_bot.access_token.token },
             params: { labels: [existing_label.title] },
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include('existing_label')
        expect(conversation.reload.label_list).to include('existing_label')
      end

      it 'matches labels case-insensitively' do
        create(:label, account: account, title: 'support')

        post api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
             headers: { api_access_token: agent_bot.access_token.token },
             params: { labels: %w[SUPPORT Support] },
             as: :json

        expect(response).to have_http_status(:success)
        # Labels are stored with their original casing, but matched case-insensitively
        expect(conversation.reload.label_list.map(&:downcase)).to include('support')
      end

      it 'allows bot to clear all labels with empty array' do
        create(:label, account: account, title: 'existing_label')
        conversation.update_labels(['existing_label'])

        post api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
             headers: { api_access_token: agent_bot.access_token.token },
             params: { labels: [] },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.label_list).to be_empty
      end

      it 'returns 422 when trying to set non-existing labels' do
        post api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
             headers: { api_access_token: agent_bot.access_token.token },
             params: { labels: %w[nonexistent_label another_bad_label] },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Labels not found')
        expect(response.parsed_body['message']).to include('nonexistent_label')
        expect(response.parsed_body['message']).to include('another_bad_label')
      end

      it 'returns 422 with only invalid labels when some labels exist' do
        existing_label = create(:label, account: account, title: 'existing_valid_label')

        post api_v1_account_conversation_labels_url(account_id: account.id, conversation_id: conversation.display_id),
             headers: { api_access_token: agent_bot.access_token.token },
             params: { labels: [existing_label.title, 'nonexistent_label'] },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Labels not found')
        expect(response.parsed_body['message']).to include('nonexistent_label')
        expect(response.parsed_body['message']).not_to include('existing_valid_label')
      end
    end
  end
end
