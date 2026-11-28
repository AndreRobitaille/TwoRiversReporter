module CouncilProfiles
  # Project a saved assessment onto the current platform without re-assessing votes.
  class ReviewedPlatformReport < SimpleDelegator
    attr_reader :sentences, :promise_assessments

    def initialize(report, platform, campaign_urls)
      super(report)
      @promise_assessments = platform.items.map { |item| finding(item, report.promise_assessments, campaign_urls) }
      # A saved campaign sentence can cite several positions, including a removed one.
      # Rebuild that part from retained source material. Keep independent council reporting.
      office = report.sentences.reject { |row| row.fetch("sources").any? { |source| campaign_urls.include?(source.fetch("url")) } }
      first = @promise_assessments.first
      campaign = if first
        [ { "text" => first.fetch("label"), "sources" => first.fetch("sources").select { |s| campaign_urls.include?(s.fetch("url")) } } ]
      else
        []
      end
      @sentences = campaign + office
    end

    private

    def finding(item, assessed, campaign_urls)
      records = item.fetch(:statements)
      versions = records.map(&:campaign_source_version).uniq
      publications = versions.map { |v| { "url" => v.source_url, "label" => [ v.publisher, v.published_on ].compact.join(" · ") } }
      primary = records.first
      matches = assessed.select do |saved|
        next false unless saved["heading"] == item.fetch(:heading) && saved["quote"].present?
        next false if item[:undertaking] == "personal_action" && %w[city_result city_progress].include?(saved["status"])
        records.any? do |record|
          saved["quote"] == record.data["supporting_quote"] &&
            saved.fetch("sources").any? { |s| s["url"] == record.campaign_source_version.source_url }
        end
      end
      # When repeats have different judgments, neither can silently supersede the other.
      verdict = matches.first if matches.pluck("status").uniq.one?
      quote = verdict ? verdict.fetch("quote") : primary.data.fetch("supporting_quote")
      records.select { |record| record.data["supporting_quote"] == quote }.each do |record|
        if (time = record.forum_clip_times[:answer])
          publications.find { |source| source["url"] == record.campaign_source_version.source_url }["answer_ms"] = time
        end
      end
      if verdict
        supporting = verdict.fetch("sources").reject { |s| campaign_urls.include?(s.fetch("url")) }
        return verdict.merge("heading" => item.fetch(:heading), "label" => item.fetch(:description), "sources" => (publications + supporting).uniq)
      end
      { "heading" => item.fetch(:heading), "label" => item.fetch(:description), "quote" => quote,
        "status" => "pending_review", "reason" => "The Council record for this position is awaiting assessment.", "sources" => publications }
    end
  end
end
