# frozen_string_literal: true

module AiAgents
  module Tools
    class HumanHandoffService
      REASON_LIMIT = 300
      CONTEXT_LIMIT = 1_500

      def initialize(ai_agent:, account:, mode:, settings:, conversation: nil, trigger_message: nil)
        @ai_agent = ai_agent
        @account = account
        @mode = mode
        @settings = settings || {}
        @conversation = conversation
        @trigger_message = trigger_message
      end

      def call(args:)
        requested_labels = normalize_labels(args['labels'])
        labels_to_apply = filter_labels(requested_labels)
        private_note = handoff_brief(args: args)

        result = {
          status: 'ok',
          terminal_action: 'handoff',
          conversation_status: 'open',
          customer_message: args['customer_message'],
          private_note_preview: private_note,
          labels_requested: requested_labels,
          labels_to_apply: labels_to_apply,
          labels_ignored: requested_labels - labels_to_apply,
          reason: args['reason']
        }

        return result if test_mode?

        execute_live_handoff!(result: result, private_note: private_note)
      end

      private

      attr_reader :ai_agent, :account, :mode, :settings, :conversation, :trigger_message

      def allowed_labels
        Array(settings['allowed_labels']).filter_map(&:presence).map(&:to_s)
      end

      def existing_account_labels
        @existing_account_labels ||= normalize_labels(account.labels.pluck(:title))
      end

      def normalize_labels(labels)
        Array(labels).filter_map(&:presence).map { |label| label.to_s.downcase }.uniq
      end

      def filter_labels(requested_labels)
        filtered = requested_labels & existing_account_labels
        return filtered if allowed_labels.empty?

        filtered & normalize_labels(allowed_labels)
      end

      def execute_live_handoff!(result:, private_note:)
        return live_error_result('conversation_required') unless conversation
        return live_error_result('trigger_message_required') unless trigger_message
        return live_error_result('handoff_already_completed') if handoff_completed?

        add_customer_message!(result[:customer_message])
        add_private_note!(private_note)
        conversation.add_labels(result[:labels_to_apply]) if result[:labels_to_apply].present?
        mark_handoff_completed!(result: result)
        conversation.bot_handoff!
        attempt_best_effort_assignment!

        result
      end

      def add_customer_message!(customer_message)
        return if customer_message.blank?

        params = {
          content: customer_message,
          private: false,
          sender_type: 'AgentBot',
          sender_id: ai_agent.agent_bot_id
        }

        Messages::MessageBuilder.new(nil, conversation.reload, params).perform
      end

      def add_private_note!(internal_note)
        params = {
          content: internal_note,
          private: true,
          sender_type: 'AgentBot',
          sender_id: ai_agent.agent_bot_id
        }

        Messages::MessageBuilder.new(nil, conversation.reload, params).perform
      end

      def attempt_best_effort_assignment!
        return if conversation.assignee.present? || conversation.assignee_agent_bot_id.present?

        AutoAssignment::AgentAssignmentService.new(
          conversation: conversation,
          allowed_agent_ids: conversation.inbox.available_agents.map(&:user_id)
        ).perform
        add_not_assigned_note! if conversation.assignee.blank?
      rescue StandardError => e
        Rails.logger.warn("[AiAgents] Best-effort human assignment failed for conversation=#{conversation.id}: #{e.class.name}: #{e.message}")
        add_not_assigned_note!
      end

      def add_not_assigned_note!
        params = {
          content: I18n.t('ai_agents.handoff_not_assigned_note', locale: conversation.account.locale),
          private: true,
          sender_type: 'AgentBot',
          sender_id: ai_agent.agent_bot_id
        }

        Messages::MessageBuilder.new(nil, conversation.reload, params).perform
      end

      def handoff_brief(args:)
        args['internal_note'].presence&.to_s&.strip&.truncate(CONTEXT_LIMIT) ||
          args['reason'].to_s.strip.truncate(REASON_LIMIT)
      end

      def mark_handoff_completed!(result:)
        conversation.update!(
          additional_attributes: current_additional_attributes.merge(
            'ai_handoff_completed' => true,
            'ai_handoff_at' => Time.current.iso8601(3),
            'ai_handoff_by_ai_agent_id' => ai_agent.id,
            'ai_handoff_message_id' => trigger_message.id,
            'ai_handoff_labels' => result[:labels_to_apply],
            'ai_handoff_reason' => result[:reason]
          )
        )
      end

      def current_additional_attributes
        conversation.additional_attributes.is_a?(Hash) ? conversation.additional_attributes.deep_stringify_keys : {}
      end

      def handoff_completed?
        current_additional_attributes['ai_handoff_completed'] == true
      end

      def live_error_result(error_code)
        {
          status: 'error',
          error_code: error_code,
          error_message: 'Human handoff could not be completed safely.'
        }
      end

      def test_mode?
        mode.to_s == 'test'
      end
    end
  end
end
