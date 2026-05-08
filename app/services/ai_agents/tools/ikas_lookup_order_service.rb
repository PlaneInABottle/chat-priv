# frozen_string_literal: true

module AiAgents
  module Tools
    class IkasLookupOrderService
      def initialize(ai_agent:, account:, mode:, settings:)
        @ai_agent = ai_agent
        @account = account
        @mode = mode
        @settings = settings || {}
      end

      def call(args:)
        {
          status: 'error',
          error_code: 'not_implemented',
          error_message: 'ikas_lookup_order is unavailable until the ikas order lookup contract is verified.'
        }
      end
    end
  end
end
