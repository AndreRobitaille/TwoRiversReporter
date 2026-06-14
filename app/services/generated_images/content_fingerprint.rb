require "digest"

module GeneratedImages
  class ContentFingerprint
    def self.for_meeting_summary(summary)
      Digest::SHA256.hexdigest(JSON.generate(meeting_payload(summary)))
    end

    def self.for_topic_briefing(briefing)
      Digest::SHA256.hexdigest(JSON.generate(topic_payload(briefing)))
    end

    def self.meeting_payload(summary)
      {
        summary_type: summary.summary_type,
        generation_data: summary.generation_data,
        content: summary.content
      }
    end

    def self.topic_payload(briefing)
      editorial_content = briefing.respond_to?(:editorial_content) ? briefing.editorial_content : nil
      record_content = briefing.respond_to?(:record_content) ? briefing.record_content : nil

      {
        generation_tier: briefing.generation_tier,
        generation_data: briefing.generation_data,
        headline: briefing.headline,
        upcoming_headline: briefing.respond_to?(:upcoming_headline) ? briefing.upcoming_headline : nil,
        editorial_content: editorial_content,
        record_content: record_content
      }
    end
  end
end
