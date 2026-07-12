# == Schema Information
#
# Table name: external_dashboard_sync_events
#
#  id         :bigint           not null, primary key
#  message    :text
#  outcome    :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  cert_id    :bigint           not null
#  run_id     :string
#
# Indexes
#
#  index_external_dashboard_sync_events_on_cert_id  (cert_id)
#  index_external_dashboard_sync_events_on_run_id   (run_id)
#
# Foreign Keys
#
#  fk_rails_...  (cert_id => certification_ship_reviews.id) ON DELETE => cascade
#
class ExternalDashboard::SyncEvent < ApplicationRecord
  belongs_to :cert, class_name: "Certification::Ship", foreign_key: :cert_id

  enum :outcome, {
    ok: 0,
    duplicate: 1,
    skipped: 2,
    failed: 3,
    retrying: 4
  }

  before_validation { self.message = message&.truncate(ExternalDashboard::Client::ERROR_MESSAGE_MAX) }
end
