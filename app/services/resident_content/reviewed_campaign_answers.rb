module ResidentContent
  # Hand-reviewed findings about a whole exchange, including answers that made
  # no promise. A correction to its wording or speaker retires the finding.
  class ReviewedCampaignAnswers
    def self.for(member)
      edition = CampaignPlatform::EDITION
      reviews = Array(edition.dig("members", member.name, "answer_reviews")).select { |review| review["flagged"] }
      return [] if reviews.empty?

      urls = edition.fetch("sources").values_at(*reviews.pluck("source"))
      sources = CampaignSource.where(election_on: edition.fetch("election"), source_url: urls)
        .select(:source_url, :published_on, :election_on, :publisher, :prepared_transcript).index_by(&:source_url)

      reviews.filter_map do |review|
        source = sources[edition.fetch("sources").fetch(review.fetch("source"))]
        segments = source&.prepared_transcript&.fetch("segments", [])
        next unless segments

        question = segments.find { |row| row["start_ms"] == review.fetch("question_ms") }
        answer = segments.find { |row| row["start_ms"] == review.fetch("answer_ms") }
        next unless question && answer && answer["speaker"] == member.name && answer["attribution"] == "reviewer_verified"
        next unless Digest::SHA256.hexdigest([ question.fetch("text"), answer.fetch("text") ].join("\n")) == review.fetch("exchange_sha256")

        review.merge("source_record" => source, "question_text" => question.fetch("text"), "answer_text" => answer.fetch("text"))
      end
    end
  end
end
