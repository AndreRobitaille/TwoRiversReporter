module CouncilHistory
  class Estimate
    TEMPLATES = {
      "votes" => [ "extract_votes", Ai::OpenAiService::MAX_MINUTES_COMPLETION_TOKENS ],
      "attendance" => [ "extract_committee_members", Ai::OpenAiService::MAX_MINUTES_COMPLETION_TOKENS ],
      "topics" => [ "extract_topics", 12_000 ], "recap" => [ "analyze_meeting_content", 12_000 ],
      "topic_triage" => [ "triage_topics", 12_000 ], "topic_refinement" => [ "refine_catchall_topic", 12_000 ],
      "topic_briefing_analysis" => [ "analyze_topic_briefing", 12_000 ], "topic_briefing_render" => [ "render_topic_briefing", 12_000 ],
      "topic_analysis" => [ "analyze_topic_summary", 12_000 ], "topic_render" => [ "render_topic_summary", 12_000 ]
    }.freeze

    def self.call(rows, from:, through:, reviewed_facts:)
      eligible = rows.select { |r| r.fetch("disposition").in?(%w[usable fetch_minutes]) }
      prior = reviewed_facts.group_by { |r| r.fetch("url") }
      quantities = Hash.new(0)
      eligible.each do |row|
        saved = Array(prior[row.fetch("documents")["minutes_pdf"]]).pluck("kind")
        quantities["votes"] += 1 if row.fetch("votes").zero? && !saved.include?("votes") && row["vote_status"] != "empty"
        quantities["attendance"] += 1 if row.fetch("attendance").zero? && !saved.include?("attendance") && row["attendance_status"] != "empty"
        quantities["recap"] += 1 if row.fetch("recaps").zero?
        quantities["topics"] += 1 if (row.fetch("documents").keys & %w[agenda_pdf agenda_html]).any? && !row["topics_status"].in?(%w[processed empty])
      end
      samples = TEMPLATES.to_h do |stage, (key, output_limit)|
        template = PromptTemplate.find_by!(key: key)
        model = Ai::OpenAiService.model_for_tier(template.model_tier)
        prices = PromptRun.where(prompt_template_key: key).order(id: :desc).limit(12).filter_map do |run|
          parameters = { model: model, messages: run.messages.map(&:symbolize_keys),
            max_completion_tokens: output_limit }
          quote = Campaigns::CostPreflight.for_parameters(parameters)
          quote[:cost_microusd] if quote[:state] == "estimate"
        end.sort
        median = prices[prices.length / 2]
        count = quantities[stage] unless stage.start_with?("topic_")
        # A destination can lack historical prompt logs. Show explicit unit
        # scenarios without pretending to know how many topics it will find.
        scenarios = [ 16_000, 64_000 ].to_h do |bytes|
          params = { model: model, messages: [ { role: "user", content: "x" * bytes } ], max_completion_tokens: output_limit }
          quote = Campaigns::CostPreflight.for_parameters(params)
          [ bytes, (quote[:cost_microusd] * 2 if quote[:state] == "estimate") ]
        end
        [ stage, { model: model, max_output_tokens: output_limit, sample_count: prices.length,
          two_attempt_microusd_by_prompt_bytes: scenarios, sample_median_request_microusd: median, candidate_count: count,
          sample_projection_with_retry_microusd: (median * count * 2 if median && count) } ]
      end
      members = Member.where(id: CampaignStatement.where(status: "accepted").select(:member_id))
      { ordinary_stages: samples, present_comparisons: Campaigns::ComparisonPreview.call(members: members, from: from, through: through),
        assumptions: "Stage projections use recent saved prompt sizes and two attempts. Topic counts, refinements and new comparison candidates emerge during processing. Each dispatch is priced against the remaining balance.",
        historical_charged_microusd: CouncilHistoryRequest.sum(:charged_microusd), historical_limit_microusd: CouncilHistoryRequest::TOTAL_LIMIT,
        pilot_charged_microusd: CouncilHistoryRequest.where(pilot: true).sum(:charged_microusd), pilot_limit_microusd: CouncilHistoryRequest::PILOT_LIMIT }
    end
  end
end
