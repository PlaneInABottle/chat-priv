class Voice::ToolEventSerializer
  PUBLIC_ACTIONS = {
    'ikas_catalog_search' => 'catalog_search',
    'ikas_lookup_order' => 'order_lookup',
    'human_handoff' => 'human_handoff',
    'request_human_handoff' => 'human_handoff',
    'end_customer_call' => 'call_ended'
  }.freeze

  def self.public_payload(event)
    {
      id: event.id,
      action: PUBLIC_ACTIONS.fetch(event.tool, 'generic'),
      status: event.status,
      created_at: event.created_at.iso8601
    }
  end
end
