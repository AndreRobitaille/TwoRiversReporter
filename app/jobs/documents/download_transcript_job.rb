module Documents
  class DownloadTranscriptJob < ApplicationJob
    queue_as :default

    def perform(meeting_id, video_url)
      # TODO: Implemented in Task 4
      raise NotImplementedError, "DownloadTranscriptJob not yet implemented"
    end
  end
end
