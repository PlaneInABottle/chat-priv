require 'administrate/base_dashboard'

class VoiceAgentDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsToSearch.with_options(searchable: true, searchable_field: [:name, :id], order: 'id DESC'),
    name: Field::String,
    enabled: Field::Boolean,
    architecture: Field::String,
    provider: Field::String,
    model: Field::String,
    voice: Field::String,
    language: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    account
    name
    enabled
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    name
    enabled
    architecture
    provider
    model
    voice
    language
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    account
    name
    enabled
    architecture
    provider
    model
    voice
    language
  ].freeze

  def display_resource(agent)
    agent.name
  end
end
