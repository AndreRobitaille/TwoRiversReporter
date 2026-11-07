class ExtractCommitteeMembersJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    Minutes::Pipeline.new(meeting_id, "attendance").call
  end
end
