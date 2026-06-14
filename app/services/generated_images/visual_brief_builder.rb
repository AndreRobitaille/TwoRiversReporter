module GeneratedImages
  class VisualBriefBuilder
    def initialize(imageable, source:, eligibility: nil, ai_service: Ai::OpenAiService.new)
      @imageable = imageable
      @source = source
      @eligibility = eligibility
      @ai_service = ai_service
    end

    def call
      composite = composite?
      @ai_service.build_generated_image_brief(
        imageable_type: @imageable.class.name,
        source_text: source_text,
        composite: composite
      )
    end

    private

    def composite?
      return false if @eligibility.nil?

      eligibility = @eligibility.respond_to?(:call) ? @eligibility.call : @eligibility
      eligibility.respond_to?(:composite?) && eligibility.composite?
    end

    def source_text
      case @source
      when MeetingSummary
        meeting_summary_source_text
      when TopicBriefing
        topic_briefing_source_text
      else
        @source.to_s
      end
    end

    def meeting_summary_source_text
      gd = @source.generation_data || {}
      approved_topics = Array(gd["item_details"]).flat_map { |item| Array(item["topics"]) }.map do |topic|
        [ topic["name"], topic["description"] ].compact.join(" — ")
      end

      sections = [
        "Meeting headline: #{gd["headline"]}".strip,
        [ "Highlights:", *Array(gd["highlights"]).map { |item| item["text"] } ].join("\n"),
        [ "Item details:", *Array(gd["item_details"]).map { |item| [ item["agenda_item_title"], item["summary"] ].compact.join(" — ") } ].join("\n"),
        [ "Approved topics:", *approved_topics ].join("\n"),
        "Visual guidance: choose one dominant resident-visible physical anchor. Prefer neighborhood physical change and household cost impacts. Do not collage multiple agenda items. For named local places/facilities, use cropped, non-identifying details rather than inventing a full replacement exterior.",
        @source.content
      ]

      sections.compact.map(&:to_s).map(&:strip).reject(&:blank?).join("\n\n")
    end

    def topic_briefing_source_text
      gd = @source.generation_data || {}
      sections = [
        "Topic: #{@source.topic.name} — #{@source.topic.description}".strip,
        "What to Watch: #{gd.dig("editorial_analysis", "what_to_watch") || gd.dig("editorial_analysis", "current_state")}".strip,
        [ "Factual record:", *Array(gd["factual_record"]).map { |item| [ item["date"], item["event"] ].compact.join(" — ") } ].join("\n"),
        @source.headline,
        @source.upcoming_headline,
        @source.editorial_content,
        @source.record_content,
        "Visual guidance: choose one dominant resident-visible physical anchor. Prefer neighborhood physical change and household cost impacts. Do not collage multiple agenda items. For named local places/facilities, use cropped, non-identifying details rather than inventing a full replacement exterior."
      ]

      sections.compact.map(&:to_s).map(&:strip).reject(&:blank?).join("\n\n")
    end
  end
end
