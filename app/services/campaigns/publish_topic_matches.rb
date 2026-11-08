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
            topic = resolve_topic(topic_id)
            link.update!(topic: topic) if topic
          end
        end
      end
    end

    def self.resolve_topic(topic_id)
      return Topic.reusable.find_by(id: topic_id) if Topic.exists?(id: topic_id)

      path = Rails.application.routes.url_helpers.topic_path(topic_id)
      destination = Redirect.find_by(source_path: path)&.destination
      surviving_id = destination.to_s[%r{\A/topics/(\d+)\z}, 1]
      Topic.reusable.find_by(id: surviving_id) if surviving_id
    end
    private_class_method :resolve_topic
  end
end
