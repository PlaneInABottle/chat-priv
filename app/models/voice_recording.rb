# == Schema Information
#
# Table name: voice_recordings
#
#  id               :bigint           not null, primary key
#  bucket           :string
#  completed_at     :datetime
#  content_type     :string
#  duration_seconds :integer
#  error_message    :text
#  metadata         :jsonb            not null
#  object_key       :string
#  started_at       :datetime
#  status           :string           default("starting"), not null
#  storage_provider :string           default("s3_compatible"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  call_id          :bigint           not null
#  egress_id        :string
#
# Indexes
#
#  index_voice_recordings_on_account_id                 (account_id)
#  index_voice_recordings_on_account_id_and_created_at  (account_id,created_at)
#  index_voice_recordings_on_account_id_and_status      (account_id,status)
#  index_voice_recordings_on_call_id                    (call_id)
#  index_voice_recordings_on_egress_id                  (egress_id) UNIQUE WHERE (egress_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (call_id => calls.id)
#
class VoiceRecording < ApplicationRecord
  STATUSES = %w[starting active completed failed].freeze
  STORAGE_PROVIDERS = %w[s3_compatible].freeze

  belongs_to :account
  belongs_to :call

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :storage_provider, presence: true, inclusion: { in: STORAGE_PROVIDERS }
  validates :egress_id, uniqueness: true, allow_blank: true

  scope :latest_first, -> { order(created_at: :desc, id: :desc) }
  scope :active, -> { where(status: %w[starting active]) }
  scope :completed, -> { where(status: 'completed') }

  def completed?
    status == 'completed'
  end

  def active?
    status.in?(%w[starting active])
  end

  def terminal?
    status.in?(%w[completed failed])
  end
end
