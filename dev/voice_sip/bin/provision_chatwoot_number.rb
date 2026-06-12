# frozen_string_literal: true

require 'json'

def required_env(key)
  ENV.fetch(key).presence || raise(ArgumentError, "#{key} is required")
end

account = Account.find(required_env('VOICE_SIP_ACCOUNT_ID'))
setting = account.voice_inbox_settings.find(required_env('VOICE_SIP_VOICE_INBOX_SETTING_ID'))
phone_number = VoiceNumber.normalize_number(required_env('VOICE_SIP_PHONE_NUMBER'))
provider = ENV.fetch('VOICE_SIP_PROVIDER', 'test_sip')
connection_name = ENV.fetch('VOICE_SIP_CONNECTION_NAME', 'Local Asterisk')

connection = account.voice_provider_connections.find_or_initialize_by(provider: provider, name: connection_name)
connection.status = ENV.fetch('VOICE_SIP_CONNECTION_STATUS', 'active')
connection.settings = {
  'kind' => 'local_asterisk',
  'sip_host' => ENV['LIVEKIT_SIP_HOST'],
  'auth_username' => ENV['LIVEKIT_SIP_AUTH_USERNAME']
}.compact
connection.save!

number = VoiceNumber.find_or_initialize_by(phone_number: phone_number)
if number.persisted? && number.account_id != account.id
  raise "Voice number #{phone_number} already belongs to account #{number.account_id}"
end

number.assign_attributes(
  account: account,
  voice_provider_connection: connection,
  voice_inbox_setting: setting,
  status: ENV.fetch('VOICE_SIP_NUMBER_STATUS', 'active'),
  livekit_inbound_trunk_id: ENV['LIVEKIT_SIP_INBOUND_TRUNK_ID'].presence,
  livekit_dispatch_rule_id: ENV['LIVEKIT_SIP_DISPATCH_RULE_ID'].presence,
  settings: {
    'dial_extension' => ENV['ASTERISK_DIAL_EXTENSION'],
    'softphone_user' => ENV['ASTERISK_SOFTPHONE_USER']
  }.compact
)
number.save!

puts JSON.pretty_generate(
  account_id: account.id,
  voice_provider_connection_id: connection.id,
  voice_number_id: number.id,
  voice_inbox_setting_id: setting.id,
  phone_number: number.phone_number,
  livekit_inbound_trunk_id: number.livekit_inbound_trunk_id,
  livekit_dispatch_rule_id: number.livekit_dispatch_rule_id
)
