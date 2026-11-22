class AutoTriageKnowledgeJob < ApplicationJob
  queue_as :default

  def perform
    proposed = KnowledgeSource.available.proposed.where(origin: %w[extracted pattern])
    if proposed.none?
      Rails.logger.info "AutoTriageKnowledgeJob: No proposed knowledge entries to triage."
      return
    end

    Rails.logger.info "AutoTriageKnowledgeJob: Triaging #{proposed.count} proposed knowledge entries..."

    ai_service = Ai::OpenAiService.new
    retrieval_service = RetrievalService.new

    entries_payload = proposed.map { |entry| entry_payload(entry) }
    captured = entries_payload.index_by { |entry| entry.fetch(:id) }

    # Retrieve existing approved KB for duplicate checking
    existing_kb = retrieval_service.format_context(
      retrieval_service.retrieve_context("civic knowledge Two Rivers", limit: 20)
    )

    response = ai_service.triage_knowledge(
      entries_json: entries_payload.to_json,
      existing_kb: existing_kb,
      source: nil
    )

    return if response.blank?

    parsed = JSON.parse(response)
    decisions = Array(parsed["decisions"])

    decisions.each do |decision|
      entry = proposed.find { |e| e.id == decision["knowledge_source_id"] }
      next unless entry

      status = { "approve" => "approved", "block" => "blocked" }[decision["action"].to_s]
      next unless status

      KnowledgeSource.transaction do
        current = KnowledgeSource.available.proposed.lock("FOR NO KEY UPDATE").find_by(id: entry.id)
        next unless current && current.updated_at == entry.updated_at && entry_payload(current) == captured.fetch(entry.id)

        current.update!(status: status)
        Rails.logger.info "AutoTriageKnowledgeJob: #{status.capitalize} '#{current.title}' — #{decision["rationale"]}"
      end
    end
  rescue JSON::ParserError => e
    Rails.logger.error("AutoTriageKnowledgeJob: Failed to parse AI response: #{e.message}")
  end

  private

  def entry_payload(entry)
    { id: entry.id, title: entry.title, body: entry.body, reasoning: entry.reasoning,
      confidence: entry.confidence, origin: entry.origin, topic_names: entry.topics.order(:name).pluck(:name) }
  end
end
