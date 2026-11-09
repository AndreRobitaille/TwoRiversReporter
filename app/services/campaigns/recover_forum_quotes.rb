module Campaigns
  # Explicitly revalidate a retained forum response, without another provider
  # request. Keep the prior version/result and all unchanged semantic matches.
  class RecoverForumQuotes
    def self.call(source, actor:)
      raise ArgumentError, "An active administrator must perform recovery" unless actor&.admin? && actor.active_for_authentication?

      source.with_lock do
        version = source.current_version
        original = version.extraction
        unless version.forum? && original&.status == "completed"
          raise ArgumentError, "Recovery requires a completed prepared forum"
        end
        parsed = ExtractedStatements.new(version.body, speaker_segments: version.prepared_transcript.fetch("segments"))
          .parse(original.data.to_json)
        return original unless parsed.fetch("counts").fetch("located_statements") > original.data.fetch("counts").fetch("located_statements")

        recovery = { "method" => "contiguous_forum_excerpt_v1", "original_extraction_id" => original.id,
          "reviewed_by_id" => actor.id, "reviewed_at" => Time.current.iso8601 }
        source.submitted_by = actor
        source.update!(prepared_transcript: source.prepared_transcript.merge("quote_recovery" => recovery))
        current = source.current_version
        extraction = ExtractSource.prepare(current)
        extraction.update!(status: "completed", data: parsed.merge("quote_recovery" => recovery),
          reused_from: original, completed_at: Time.current)
        PublishStatements.call(extraction)
        matching = MatchTopics.prepare(current.reload)
        PublishTopicMatches.call(matching)
        MatchCampaignTopicsJob.perform_later(source.id) if matching.status == "pending"
        extraction
      end
    end
  end
end
