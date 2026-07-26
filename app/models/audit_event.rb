# A durable record of the destructive admin actions. Every field that names
# something is stored twice: once as an association, and once as a snapshot
# string. The association is convenient while the target exists; the snapshot
# is what survives, and these are precisely the actions that delete their own
# subjects.
class AuditEvent < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :action, presence: true

  def self.record!(actor:, action:, subject: nil, label: nil, request: nil, metadata: {})
    create!(
      actor: actor,
      actor_email: actor&.email_address,
      action: action,
      subject: subject,
      subject_label: label,
      metadata: metadata,
      ip_address: request&.remote_ip
    )
  end
end
