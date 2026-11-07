class ExtractVotesJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    Minutes::Pipeline.new(meeting_id, "votes").call
  end
end
