module Admin
  class QuestionnaireProgress
    attr_reader :extraction, :matched, :unresolved, :unlinked

    def initialize(version)
      @extraction = version&.extraction
      @matched, @unresolved = if extraction&.status == "completed"
        extraction.campaign_statements.includes(:member).order(:sequence).partition { |statement| statement.status == "accepted" }
      else
        [ [], [] ]
      end
      catalog_article = Campaigns::ElectionBackfill.catalog_article(version) if unresolved.any?
      outside_council = catalog_article&.fetch("outside_council_records", []) || []
      @unlinked, @unresolved = unresolved.partition do |statement|
        statement.exception == "unknown_person" && outside_council.include?(statement.data["source_name"])
      end
    end

    def needs_attention?
      unresolved.any? || %w[budget_paused failed incomplete uncertain oversized].include?(extraction&.status)
    end

    def can_start?
      return @can_start if defined?(@can_start)

      @can_start = Campaigns::AnalysisRun.for(extraction).present?
    end

    def tone
      return "attention" if needs_attention?
      return "clear" if extraction&.status == "completed"

      "pending"
    end

    def label
      case extraction&.status
      when "completed" then unresolved.any? ? "Review needed" : "Analysis complete"
      when "running" then "Analysis in progress"
      when "budget_paused" then can_start? ? "Ready to analyze" : "Analysis hasn’t run"
      when "failed", "incomplete", "uncertain" then "Analysis needs attention"
      when "oversized" then "Source text needs to be split"
      else "Analysis pending"
      end
    end

    def guidance
      case extraction&.status
      when "completed"
        if unresolved.any?
          "Check the items below against the original article. Only statements that passed the source and identity checks are linked to Council member records."
        else
          matched.any? ? "Checked statements are linked to Council member records." : "Analysis is complete. No statements from this source are linked to a Council member record."
        end
      when "budget_paused"
        can_start? ? "Start analysis of these answers. Checked statements can appear on Council member records when this source finishes." :
          "The answers are saved. A site administrator needs to enable analysis for this source."
      when "running"
        "The app is extracting statements and checking them against the saved answers."
      when "oversized"
        "Review how the source is divided before trying analysis again. The original answers are still saved."
      when "failed", "incomplete", "uncertain"
        "The answers are saved. Check the processing details before trying analysis again."
      else
        "Source saved. The app checks for existing analysis and starts processing when this source is ready."
      end
    end
  end
end
