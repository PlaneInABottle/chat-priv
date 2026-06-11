class Voice::InboundCallBuilder
  attr_reader :inbox, :from_number, :call_sid, :provider, :extra_meta

  def self.perform!(inbox:, from_number:, call_sid:, provider: :twilio, extra_meta: {})
    new(inbox: inbox, from_number: from_number, call_sid: call_sid,
        provider: provider, extra_meta: extra_meta).perform!
  end

  def initialize(inbox:, from_number:, call_sid:, provider: :twilio, extra_meta: {})
    @inbox = inbox
    @from_number = from_number
    @call_sid = call_sid
    @provider = provider.to_sym
    @extra_meta = extra_meta || {}
  end

  def perform!
    existing = find_existing_call
    if existing
      start_recording!(existing)
      return existing
    end

    call = ActiveRecord::Base.transaction do
      contact_inbox = ensure_contact_inbox!
      contact = contact_inbox.contact
      conversation = resolve_conversation!(contact, contact_inbox)
      call = create_call!(contact, conversation)
      message = Voice::CallMessageBuilder.new(call).perform!
      call.update!(message_id: message.id)
      call
    end
    start_recording!(call)
    call
  rescue ActiveRecord::RecordNotUnique
    find_existing_call || raise
  end

  private

  def account
    inbox.account
  end

  def find_existing_call
    Call.where(account_id: account.id, inbox_id: inbox.id)
        .find_by(provider: provider, provider_call_id: call_sid)
  end

  def ensure_contact_inbox!
    sid = source_id_for_provider
    existing = inbox.contact_inboxes.find_by(source_id: sid)
    return existing if existing

    ContactInbox.create!(contact: ensure_contact!, inbox: inbox, source_id: sid)
  rescue ActiveRecord::RecordNotUnique
    inbox.contact_inboxes.find_by!(source_id: sid)
  end

  def ensure_contact!
    return ensure_livekit_contact! if provider == :livekit

    contact = account.contacts.find_or_create_by!(phone_number: from_number) do |record|
      record.name = contact_name.presence || from_number
    end
    contact.update!(name: contact_name) if contact_name.present? && contact.name == from_number
    contact
  end

  def ensure_livekit_contact!
    account.contacts.find_or_create_by!(identifier: source_id_for_provider) do |record|
      record.name = contact_name.presence || from_number.presence || 'Voice caller'
      record.phone_number = from_number if from_number.to_s.match?(/\A\+[1-9]\d{1,14}\z/)
    end
  end

  def contact_name
    extra_meta['contact_name'].presence || extra_meta[:contact_name].presence
  end

  def source_id_for_provider
    return "voice:#{from_number.presence || call_sid}" if provider == :livekit
    return from_number unless provider == :whatsapp

    digits = from_number.to_s.delete_prefix('+')
    Whatsapp::PhoneNumberNormalizationService.new(inbox).normalize_and_find_contact_by_provider(digits, :cloud)
  end

  def resolve_conversation!(contact, contact_inbox)
    reusable = if inbox.lock_to_single_conversation
                 contact_inbox.conversations.last
               else
                 contact_inbox.conversations.where.not(status: :resolved).last
               end
    return reusable if reusable

    account.conversations.create!(
      contact_inbox_id: contact_inbox.id,
      inbox_id: inbox.id,
      contact_id: contact.id,
      status: :open
    )
  end

  def create_call!(contact, conversation)
    call = Call.create!(
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: contact,
      provider: provider,
      direction: :incoming,
      status: 'ringing',
      provider_call_id: call_sid,
      meta: { 'initiated_at' => Time.zone.now.to_i, 'from_number' => from_number }.merge(extra_meta.stringify_keys)
    )
    call.update!(conference_sid: call.default_conference_sid) if call.twilio?
    call
  end

  def start_recording!(call)
    Voice::Recordings::StartService.perform(call: call)
  rescue StandardError => e
    Rails.logger.warn("voice recording start failed call_id=#{call.id} error=#{e.class.name}: #{e.message}")
  end
end
