module Campaigns
  # A longer edition can preserve an already reviewed newspaper answer verbatim.
  # Compare the complete answer under its named heading and question before
  # reusing the excerpt's editorial references.
  class ReviewedQuestionnaireExcerpt
    def self.retained?(rows, current)
      previous = rows.first.campaign_source_version
      return false unless previous.coverage == "selected_excerpts" && current&.coverage == "full_article"
      return false if current.extraction&.status == "completed"
      return false unless previous.slice(:source_url, :published_on, :election_on, :publisher) == current.slice(:source_url, :published_on, :election_on, :publisher)
      edition = ResidentContent::CampaignPlatform::EDITION
      key = edition.fetch("sources").key(previous.source_url)
      name = rows.first.data.fetch("source_name")
      expected = edition.dig("members", name, "digests", key)
      return false unless expected && previous.election_on.iso8601 == edition.fetch("election") &&
        ResidentContent::CampaignPlatform.source_digest(rows) == expected

      names = ElectionBackfill.candidates_on(current.election_on)
      sections = current.body.split(/^(#{Regexp.union(names)})[ \t]*$/).drop(1).each_slice(2).to_a
      return false unless sections.map(&:first).sort == names.sort && (section = sections.to_h[name])

      participant = rows.first.campaign_extraction.data.fetch("participants").find { |person| person["name"] == name }
      return false unless participant
      participant.fetch("answers").all? do |answer|
        question = answer.fetch("question")
        text = answer.fetch("passage").delete_prefix("#{name}: ").delete_prefix("#{name.split.last}: ").squish
        parts = section.split(/^#{Regexp.escape(question)}[ \t]*$/, -1)
        parts.size == 2 && parts.last.split(/\n\s*\n(?=[^\n]*\?\s*$)/).first.to_s.squish == text
      end
    end
  end
end
