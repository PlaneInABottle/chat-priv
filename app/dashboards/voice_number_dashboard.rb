require 'administrate/base_dashboard'

class VoiceNumberDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsToSearch.with_options(searchable: true, searchable_field: [:name, :id], order: 'id DESC'),
    voice_provider_connection: Field::BelongsTo,
    voice_inbox_setting: Field::BelongsTo,
    inbox: Field::HasOne,
    voice_agent: Field::HasOne,
    phone_number: Field::String,
    status: Field::Select.with_options(collection: VoiceNumber::STATUSES),
    livekit_inbound_trunk_id: Field::String,
    livekit_dispatch_rule_id: Field::String,
    settings: RedactedJsonField,
    last_error: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    account
    phone_number
    status
    voice_provider_connection
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    voice_provider_connection
    voice_inbox_setting
    phone_number
    status
    livekit_inbound_trunk_id
    livekit_dispatch_rule_id
    settings
    last_error
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    account
    voice_provider_connection
    voice_inbox_setting
    phone_number
    status
    livekit_inbound_trunk_id
    livekit_dispatch_rule_id
    last_error
  ].freeze

  COLLECTION_FILTERS = {
    active: ->(resources) { resources.where(status: 'active') },
    netgsm: ->(resources) { resources.joins(:voice_provider_connection).where(voice_provider_connections: { provider: 'netgsm' }) },
    test_sip: ->(resources) { resources.joins(:voice_provider_connection).where(voice_provider_connections: { provider: 'test_sip' }) }
  }.freeze

  def display_resource(number)
    number.phone_number
  end
end
