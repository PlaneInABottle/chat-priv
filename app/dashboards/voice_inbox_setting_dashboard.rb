require 'administrate/base_dashboard'

class VoiceInboxSettingDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsToSearch.with_options(searchable: true, searchable_field: [:name, :id], order: 'id DESC'),
    inbox: Field::BelongsTo,
    voice_agent: Field::BelongsTo,
    recording_enabled: Field::Boolean,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    account
    inbox
    voice_agent
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    inbox
    voice_agent
    recording_enabled
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    account
    inbox
    voice_agent
    recording_enabled
  ].freeze

  def display_resource(setting)
    "Voice inbox setting ##{setting.id}"
  end
end
