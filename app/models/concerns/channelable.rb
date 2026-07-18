module Channelable
  extend ActiveSupport::Concern
  included do
    validates :account_id, presence: true
    belongs_to :account
    has_one :inbox, as: :channel, dependent: :destroy_async, touch: true
    after_update :create_audit_log_entry
  end

  def create_audit_log_entry; end

  def supports_ai_input_select?
    false
  end

  def supports_ai_catalog_product_images?
    false
  end
end

Channelable.prepend_mod_with('Channelable')
