require 'administrate/base_dashboard'

class VoiceProviderConnectionDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsToSearch.with_options(searchable: true, searchable_field: [:name, :id], order: 'id DESC'),
    voice_numbers: Field::HasMany,
    provider: Field::Select.with_options(collection: VoiceProviderConnection::PROVIDERS),
    name: Field::String,
    status: Field::Select.with_options(collection: VoiceProviderConnection::STATUSES),
    settings: Field::String,
    last_error: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    account
    provider
    name
    status
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    voice_numbers
    provider
    name
    status
    settings
    last_error
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    account
    provider
    name
    status
    settings
    last_error
  ].freeze

  COLLECTION_FILTERS = {
    active: ->(resources) { resources.where(status: 'active') },
    netgsm: ->(resources) { resources.where(provider: 'netgsm') },
    test_sip: ->(resources) { resources.where(provider: 'test_sip') }
  }.freeze

  def display_resource(connection)
    "#{connection.provider}: #{connection.name}"
  end
end
