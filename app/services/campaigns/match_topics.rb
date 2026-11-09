module Campaigns
  # A shared semantic match, not a promise rating or an action/outcome finding.
  # The topic catalog is pinned when prepared; ordinary page reads and unrelated
  # topic changes do not cause a new analysis of the same campaign source.
  class MatchTopics
    MAX_CONTEXT_CHARS = 150_000

    def self.prepare(version)
      existing = version.topic_matching
      return existing if existing
      extraction = version.extraction
      return unless extraction&.status == "completed"

      context = {
        "statements" => extraction.campaign_statements.order(:sequence).filter_map do |statement|
          next unless statement.exception.nil? || statement.exception.in?(%w[unknown_person ambiguous_person])
          statement.data.slice("source_name", "question", "kind", "summary", "supporting_quote", "conditions", "timeframe")
            .merge("sequence" => statement.sequence)
        end,
        "topics" => Topic.reusable.order(:id).includes(:topic_aliases).map do |topic|
          { "id" => topic.id, "name" => topic.canonical_name.presence || topic.name,
            "description" => topic.description, "aliases" => topic.topic_aliases.map(&:name).sort }
        end
      }
      previous = CampaignExtraction.joins(:campaign_source_version)
        .where(campaign_source_versions: { campaign_source_id: version.campaign_source_id }, purpose: "topic_matching", status: "completed")
        .where.not(campaign_source_version_id: version.id).order(id: :desc).first
      retained = retained_matches(previous, context.fetch("statements"))
      if retained.any?
        context["statements"].reject! { |statement| retained.any? { |match| match.fetch("sequence") == statement.fetch("sequence") } }
        context["reused_matches"] = retained
      end
      parameters = context.fetch("statements").empty? ? {} : Ai::OpenAiService.campaign_topic_matching_parameters(context.except("reused_matches"))
      attributes = { campaign_source_version: version, purpose: "topic_matching", context: context,
        parameters: parameters, input_key: CouncilProfiles::ReserveAiSpend.request_digest(
          purpose: "topic_matching", source_version: version.version_key, parameters: parameters) }
      attributes[:reused_from] = previous if retained.any?
      if context.fetch("statements").empty?
        attributes.merge!(status: "completed", data: { "matches" => retained }, completed_at: Time.current)
      end
      CampaignExtraction.create!(attributes)
    rescue Ai::OpenAiService::InputTooLargeError
      CampaignExtraction.create!(campaign_source_version: version, purpose: "topic_matching", context: context,
        input_key: CouncilProfiles::ReserveAiSpend.request_digest(purpose: "topic_matching", version: version.version_key, context: context),
        status: "oversized", error_code: "matching_requires_partition")
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      version.reload.topic_matching || raise
    end

    def self.call(version, budget_run: nil)
      stage = prepare(version)
      return unless stage
      if stage.context.fetch("statements").empty? || stage.context.fetch("topics").empty?
        stage.with_lock do
          if stage.status == "pending"
            data = { "matches" => stage.context.fetch("statements").map do |statement|
              { "sequence" => statement.fetch("sequence"), "status" => "no_match", "topic_ids" => [], "reason" => "No approved topic candidates were available." }
            end }
            stage.update!(status: "completed", data: parse_response(stage, data.to_json), completed_at: Time.current)
          end
        end
        return stage
      end
      return stage unless stage.claim!(budget_run)
      raise CouncilProfiles::ReserveAiSpend::Paused, "missing_budget" unless budget_run

      response = Ai::OpenAiService.new.extract_campaign_source(parameters: stage.parameters.deep_symbolize_keys,
        request_recorder: CouncilProfiles::RequestRecorder.new(stage))
      data = parse_response(stage, response)
      stage.update!(status: "completed", data: data, completed_at: Time.current)
      stage
    rescue CouncilProfiles::ReserveAiSpend::Paused => e
      stage.update!(status: "budget_paused", error_code: e.message, attempts: stage.attempts - 1)
      stage
    rescue JSON::ParserError, TopicMatches::InvalidResponse => e
      stage.update!(status: "failed", error_code: e.class.name)
      stage
    rescue Ai::OpenAiService::IncompleteResponseError
      stage.update!(status: "incomplete", error_code: "incomplete_response")
      stage
    rescue StandardError => e
      stage&.update!(status: "uncertain", error_code: e.class.name) if stage&.status == "running"
      raise
    end

    def self.parse_response(stage, response)
      fresh = TopicMatches.new(stage.context).parse(response).fetch("matches")
      { "matches" => (fresh + stage.context.fetch("reused_matches", [])).sort_by { |match| match.fetch("sequence") } }
    end

    def self.retained_matches(previous, statements)
      return [] unless previous
      fields = %w[source_name question kind summary supporting_quote conditions timeframe]
      old = previous.campaign_source_version.extraction.campaign_statements.index_by(&:sequence)
      matches = previous.data.fetch("matches").index_by { |match| match.fetch("sequence") }
      statements.filter_map do |statement|
        sequence = statement.fetch("sequence")
        matches[sequence] if old[sequence]&.data&.slice(*fields) == statement.slice(*fields)
      end
    end
    private_class_method :retained_matches
  end
end
