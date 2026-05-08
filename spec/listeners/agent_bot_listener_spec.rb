require 'rails_helper'
describe AgentBotListener do
  include ActiveJob::TestHelper

  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:agent_bot) { create(:agent_bot) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: user) }

  before do
    clear_enqueued_jobs
  end

  describe '#message_created' do
    let(:event_name) { 'message.created' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, message: message) }
    let!(:message) do
      create(:message, message_type: 'outgoing',
                       account: account, inbox: inbox, conversation: conversation)
    end

    context 'when agent bot is not configured' do
      it 'does not send message to agent bot' do
        expect(AgentBots::WebhookJob).to receive(:perform_later).exactly(0).times
        listener.message_created(event)
      end
    end

    context 'when agent bot is configured' do
      it 'sends message to agent bot' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        expect(AgentBots::WebhookJob).to receive(:perform_later).with(
          agent_bot.outgoing_url, message.webhook_data.merge(event: 'message_created'),
          :agent_bot_webhook, secret: agent_bot.secret, delivery_id: instance_of(String)
        ).once
        listener.message_created(event)
      end

      it 'does not send message to agent bot if url is empty' do
        agent_bot = create(:agent_bot, outgoing_url: '')
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        expect(AgentBots::WebhookJob).not_to receive(:perform_later)
        listener.message_created(event)
      end

      context 'when conversation has a different assignee agent bot' do
        let!(:conversation_bot) { create(:agent_bot) }

        before do
          create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
          conversation.update!(assignee_agent_bot: conversation_bot, assignee: nil)
        end

        it 'sends message to both bots exactly once' do
          payload = message.webhook_data.merge(event: 'message_created')

          expect(AgentBots::WebhookJob).to receive(:perform_later).with(
            agent_bot.outgoing_url, payload, :agent_bot_webhook,
            secret: agent_bot.secret, delivery_id: instance_of(String)
          ).once
          expect(AgentBots::WebhookJob).to receive(:perform_later).with(
            conversation_bot.outgoing_url, payload, :agent_bot_webhook,
            secret: conversation_bot.secret, delivery_id: instance_of(String)
          ).once

          listener.message_created(event)
        end
      end

      it 'does not send message for ai bots even if outgoing_url is present' do
        ai_bot = create(:ai_agent, account: account).agent_bot
        ai_bot.update_column(:outgoing_url, 'https://example.com/webhook')
        create(:agent_bot_inbox, inbox: inbox, agent_bot: ai_bot)

        expect(AgentBots::WebhookJob).not_to receive(:perform_later)

        listener.message_created(event)
      end

      it 'enqueues live AI response job for eligible incoming customer messages' do
        ai_bot = create(:ai_agent, :with_human_handoff_tool, account: account, enabled: true).agent_bot
        create(:agent_bot_inbox, inbox: inbox, agent_bot: ai_bot)
        incoming_message = create(:message,
                                  account: account,
                                  inbox: inbox,
                                  conversation: conversation,
                                  message_type: 'incoming',
                                  sender: conversation.contact)
        incoming_event = Events::Base.new(event_name, Time.zone.now, message: incoming_message)

        expect { listener.message_created(incoming_event) }
          .to have_enqueued_job(AgentBots::AiResponseJob).with(incoming_message).on_queue('high')
      end

      it 'does not enqueue live AI response job for private notes' do
        ai_bot = create(:ai_agent, :with_human_handoff_tool, account: account, enabled: true).agent_bot
        create(:agent_bot_inbox, inbox: inbox, agent_bot: ai_bot)
        private_note = create(:message,
                              account: account,
                              inbox: inbox,
                              conversation: conversation,
                              message_type: 'incoming',
                              private: true,
                              sender: conversation.contact)
        private_event = Events::Base.new(event_name, Time.zone.now, message: private_note)

        expect { listener.message_created(private_event) }
          .not_to have_enqueued_job(AgentBots::AiResponseJob)
      end

      it 'does not enqueue live AI response job after ai handoff is completed' do
        ai_bot = create(:ai_agent, :with_human_handoff_tool, account: account, enabled: true).agent_bot
        create(:agent_bot_inbox, inbox: inbox, agent_bot: ai_bot)
        conversation.update!(additional_attributes: { 'ai_handoff_completed' => true })
        incoming_message = create(:message,
                                  account: account,
                                  inbox: inbox,
                                  conversation: conversation,
                                  message_type: 'incoming',
                                  sender: conversation.contact)
        incoming_event = Events::Base.new(event_name, Time.zone.now, message: incoming_message)

        expect { listener.message_created(incoming_event) }
          .not_to have_enqueued_job(AgentBots::AiResponseJob)
      end
    end
  end

  describe '#message_updated' do
    let(:event_name) { 'message.updated' }

    it 'preserves webhook behavior for webhook bots' do
      incoming_message = create(:message,
                                account: account,
                                inbox: inbox,
                                conversation: conversation,
                                message_type: 'incoming',
                                sender: conversation.contact)
      event = Events::Base.new(event_name, Time.zone.now, message: incoming_message)
      create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)

      expect(AgentBots::WebhookJob).to receive(:perform_later).with(agent_bot.outgoing_url,
                                                                    incoming_message.webhook_data.merge(event: 'message_updated')).once

      listener.message_updated(event)
    end

    it 'does not enqueue live AI response job for ai bots on updates' do
      ai_bot = create(:ai_agent, :with_human_handoff_tool, account: account, enabled: true).agent_bot
      create(:agent_bot_inbox, inbox: inbox, agent_bot: ai_bot)
      incoming_message = create(:message,
                                account: account,
                                inbox: inbox,
                                conversation: conversation,
                                message_type: 'incoming',
                                sender: conversation.contact)
      event = Events::Base.new(event_name, Time.zone.now, message: incoming_message)

      expect { listener.message_updated(event) }
        .not_to have_enqueued_job(AgentBots::AiResponseJob)
    end
  end

  describe '#conversation_opened' do
    it 'preserves webhook-only behavior' do
      create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
      event = Events::Base.new('conversation.opened', Time.zone.now, conversation: conversation)

      expect(AgentBots::WebhookJob).to receive(:perform_later).once
      expect { listener.conversation_opened(event) }.not_to have_enqueued_job(AgentBots::AiResponseJob)
    end
  end

  describe '#conversation_resolved' do
    it 'preserves webhook-only behavior' do
      create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
      event = Events::Base.new('conversation.resolved', Time.zone.now, conversation: conversation)

      expect(AgentBots::WebhookJob).to receive(:perform_later).once
      expect { listener.conversation_resolved(event) }.not_to have_enqueued_job(AgentBots::AiResponseJob)
    end
  end

  describe '#conversation_status_changed' do
    let(:event_name) { 'conversation.status_changed' }
    let(:changed_attributes) { { status: %w[open pending] } }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, changed_attributes: changed_attributes) }

    context 'when agent bot is not configured' do
      it 'does not send webhook' do
        expect(AgentBots::WebhookJob).not_to receive(:perform_later)
        listener.conversation_status_changed(event)
      end
    end

    context 'when agent bot is configured on inbox' do
      it 'sends webhook with changed_attributes' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        expect(AgentBots::WebhookJob).to receive(:perform_later).with(
          agent_bot.outgoing_url,
          hash_including(event: 'conversation_status_changed', account: account.webhook_data, changed_attributes: anything),
          :agent_bot_webhook,
          hash_including(secret: agent_bot.secret)
        ).once
        listener.conversation_status_changed(event)
      end
    end

    context 'when conversation is assigned to an agent bot' do
      before do
        conversation.update!(assignee_agent_bot: agent_bot, assignee: nil)
      end

      it 'sends webhook to the assigned agent bot' do
        expect(AgentBots::WebhookJob).to receive(:perform_later).with(
          agent_bot.outgoing_url,
          hash_including(event: 'conversation_status_changed', changed_attributes: anything),
          :agent_bot_webhook,
          hash_including(secret: agent_bot.secret)
        ).once
        listener.conversation_status_changed(event)
      end
    end
  end

  describe '#conversation_updated' do
    let(:event_name) { 'conversation.updated' }

    context 'when agent bot is not configured' do
      let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation) }

      it 'does not send webhook' do
        expect(AgentBots::WebhookJob).not_to receive(:perform_later)
        listener.conversation_updated(event)
      end
    end

    context 'when agent bot is configured on inbox' do
      let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation) }

      it 'sends webhook to the inbox agent bot with changed_attributes' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        expect(AgentBots::WebhookJob).to receive(:perform_later).with(
          agent_bot.outgoing_url,
          conversation.webhook_data.merge(event: 'conversation_updated', changed_attributes: nil),
          :agent_bot_webhook, secret: agent_bot.secret, delivery_id: instance_of(String)
        ).once
        listener.conversation_updated(event)
      end
    end

    context 'when conversation is assigned to an agent bot' do
      let!(:event) do
        Events::Base.new(event_name, Time.zone.now, conversation: conversation,
                                                    changed_attributes: { 'assignee_agent_bot_id' => [nil, agent_bot.id] })
      end

      before do
        conversation.update!(assignee_agent_bot: agent_bot, assignee: nil)
      end

      it 'sends webhook with changed_attributes to the assigned agent bot' do
        expected_changed_attributes = [{ 'assignee_agent_bot_id' => { previous_value: nil, current_value: agent_bot.id } }]
        expect(AgentBots::WebhookJob).to receive(:perform_later).with(
          agent_bot.outgoing_url,
          conversation.webhook_data.merge(
            event: 'conversation_updated',
            changed_attributes: expected_changed_attributes
          ),
          :agent_bot_webhook, secret: agent_bot.secret, delivery_id: instance_of(String)
        ).once
        listener.conversation_updated(event)
      end
    end
  end

  describe '#conversation_resolved' do
    let(:event_name) { 'conversation.resolved' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation) }

    context 'when agent bot is configured' do
      it 'sends account details in the conversation payload' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        expect(AgentBots::WebhookJob).to receive(:perform_later).with(
          agent_bot.outgoing_url,
          hash_including(event: 'conversation_resolved', account: account.webhook_data),
          :agent_bot_webhook,
          hash_including(secret: agent_bot.secret)
        ).once
        listener.conversation_resolved(event)
      end
    end
  end

  describe '#webwidget_triggered' do
    let(:event_name) { 'webwidget.triggered' }

    context 'when agent bot is configured' do
      it 'send message to agent bot URL' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)

        event = double
        allow(event).to receive(:data)
          .and_return(
            {
              contact_inbox: conversation.contact_inbox,
              event_info: { country: 'US' }
            }
          )
        expect(AgentBots::WebhookJob).to receive(:perform_later)
          .with(
            agent_bot.outgoing_url,
            conversation.contact_inbox.webhook_data.merge(event: 'webwidget_triggered', event_info: { country: 'US' }),
            :agent_bot_webhook, secret: agent_bot.secret, delivery_id: instance_of(String)
          ).once

        listener.webwidget_triggered(event)
      end

      it 'does not enqueue live AI response job' do
        ai_bot = create(:ai_agent, :with_human_handoff_tool, account: account, enabled: true).agent_bot
        create(:agent_bot_inbox, inbox: inbox, agent_bot: ai_bot)

        event = double
        allow(event).to receive(:data)
          .and_return(
            {
              contact_inbox: conversation.contact_inbox,
              event_info: { country: 'US' }
            }
          )

        expect { listener.webwidget_triggered(event) }.not_to have_enqueued_job(AgentBots::AiResponseJob)
      end
    end
  end
end
