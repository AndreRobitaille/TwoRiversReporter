module Campaigns
  class PublishTopicMatches
    def self.call(stage)
      return unless stage&.purpose == "topic_matching" && stage.status == "completed"
      stage.with_lock do
        statements = stage.campaign_source_version.extraction.campaign_statements.where(status: "accepted").index_by(&:sequence)
        stage.data.fetch("matches").each do |match|
          statement = statements[match.fetch("sequence")]
          next unless statement && match.fetch("status") == "matched"
          match.fetch("topic_ids").each do |topic_id|
            link = stage.campaign_statement_topics.find_or_initialize_by(campaign_statement: statement, original_topic_id: topic_id)
            next if link.persisted? # Preserve a subsequent topic merge.
            topic = Topic.reusable.find_by(id: topic_id)
            link.update!(topic: topic) if topic
          end
        end
      end
    end
  end
end
