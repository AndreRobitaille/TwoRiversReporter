module Campaigns
  # Private, operator-supplied snapshots. Source URLs and source-local sequence
  # numbers survive database moves. Database IDs do not identify a civic fact.
  class ReviewedImport
    SOURCES = ResidentContent::CampaignPlatform::EDITION.fetch("sources").values.freeze

    def self.export
      SOURCES.map do |url|
        source = CampaignSource.find_by!(source_url: url)
        version = source.current_version
        matching = version.topic_matching
        raise "Incomplete source" unless version.extraction.status == "completed" && matching.status == "completed"
        topics = matching.data.fetch("matches").flat_map { |m| m.fetch("topic_ids") }.uniq.to_h do |id|
          [ id, Topic.find_by(id: id)&.name ]
        end
        { "source" => source.attributes.slice(*CampaignSource::SNAPSHOT_FIELDS), "sha256" => version.content_sha256,
          "statements" => version.extraction.data, "matches" => matching.data.fetch("matches"), "topics" => topics }
      end
    end

    def self.call(records, actor:)
      raise ArgumentError, "Expected the reviewed election sources" unless records.map { |r| r.dig("source", "source_url") }.sort == SOURCES.sort
      CampaignSource.transaction do
        records.each do |row|
          attrs = row.fetch("source").slice(*CampaignSource::SNAPSHOT_FIELDS)
          raise "Source identity changed" unless attrs.fetch("election_on") == "2024-04-02" &&
            Digest::SHA256.hexdigest(attrs.fetch("body")) == row.fetch("sha256")
          source = CampaignSource.find_or_initialize_by(source_url: attrs.fetch("source_url"))
          source.update!(attrs.merge(submitted_by: actor)) if source.new_record?
          raise "Different destination source" unless source.attributes.slice(*attrs.keys).as_json == attrs
          version = source.current_version
          extraction = Campaigns::ExtractSource.prepare(version)
          saved = row.fetch("statements")
          if extraction.status == "completed"
            raise "Different accepted extraction" unless extraction.data == saved
          elsif extraction.requests.exists?
            raise "Destination extraction has existing requests"
          else
            extraction.update!(status: "completed", completed_at: Time.current, data: saved)
          end
          Campaigns::PublishStatements.call(extraction)
          verify_edition!(extraction)
          import_topics(version.reload, row)
        end
      end
    end

    def self.verify_edition!(extraction)
      edition = ResidentContent::CampaignPlatform::EDITION
      source = edition.fetch("sources").key(extraction.campaign_source_version.source_url)
      edition.fetch("members").each do |name, review|
        records = extraction.campaign_statements.where(member: Member.find_by!(name: name), status: "accepted")
        digest = ResidentContent::CampaignPlatform.source_digest(records)
        raise "Reviewed campaign statements changed for #{name}" unless digest == review.fetch("digests").fetch(source)
      end
    end

    def self.import_topics(version, row)
      stage = Campaigns::MatchTopics.prepare(version)
      return if stage.status == "completed"
      raise "Destination topic matching has existing requests" if stage.requests.exists?
      sequences = stage.context.fetch("statements").pluck("sequence")
      results = row.fetch("matches").filter_map do |match|
        next unless sequences.include?(match.fetch("sequence"))
        names = match.fetch("topic_ids").map { |id| row.fetch("topics").fetch(id.to_s) }
        ids = names.map { |name| Topic.reusable.find_by(name: name)&.id if name.present? }
        if ids.any?(&:nil?)
          match.merge("topic_ids" => [], "status" => "unresolved", "reason" => "Reviewed topic identity is unavailable in the current record.")
        else
          match.merge("topic_ids" => ids.uniq)
        end
      end
      data = Campaigns::MatchTopics.parse_response(stage, { matches: results }.to_json)
      stage.update!(status: "completed", data: data, completed_at: Time.current)
      Campaigns::PublishTopicMatches.call(stage)
    end
    private_class_method :verify_edition!, :import_topics
  end
end
