class ExtractCommitteeMembersJob < ApplicationJob
  queue_as :default

  def perform(meeting_id, refresh: false)
    Minutes::Pipeline.new(meeting_id, "attendance", refresh: refresh).call
  end
end
