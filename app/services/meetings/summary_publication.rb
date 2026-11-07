module Meetings
  # Serializes source withdrawal and summary publication, including a first
  # summary with no row to lock. Never hold these locks during provider calls.
  # An advisory lock avoids upgrading the Meeting row lock while a source
  # writer already owns a Document row (minutes publication locks the reverse).
  class SummaryPublication
    def self.with_lock(*meeting_ids)
      ApplicationRecord.transaction do
        ApplicationRecord.uncached do
          meeting_ids.compact.uniq.sort.each do |id|
            identity = ApplicationRecord.connection.quote("meeting-summary:#{id}")
            ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{identity}, 0))")
          end
          yield
        end
      end
    end

    def self.version(summary)
      summary&.attributes&.slice("id", "updated_at")
    end

    def self.publish(meeting:, summary_type:, expected:, sources:, topic_context: nil)
      with_lock(meeting.id) do
        persist = lambda do
          current = meeting.meeting_summaries.where(summary_type: summary_type).lock.first
          if version(current) == expected && Topics::GenerationEvidence.sources_current?(sources)
            yield
          end
        end
        # Match withdrawal's topic-before-summary lock order.
        topic_context ? topic_context.with_current(&persist) : persist.call
      end
    end

    def self.with_current(summary)
      with_lock(summary.meeting_id) do
        current = MeetingSummary.published.lock.find_by(id: summary.id)
        if current && version(current) == version(summary) &&
            Topics::GenerationEvidence.sources_current?(current.generation_data&.dig("source_catalog"))
          yield
        end
      end
    end
  end
end
