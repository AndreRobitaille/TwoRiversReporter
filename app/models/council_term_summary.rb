class CouncilTermSummary < ApplicationRecord
  belongs_to :member

  # Commit the weekly claim before transport. A timeout or duplicate worker
  # cannot spend another call for this member in the same Tuesday cycle.
  def refresh!(cycle, evidence, authorized_run: nil)
    with_lock do
      return if attempted_cycle && attempted_cycle >= cycle
      if evidence_digest == evidence.digest
        sources = evidence.fact_keys.zip(evidence.facts).to_h
        refresh_citations(sentences, sources)
        refresh_citations(promise_assessments, sources)
        save! if changed?
        return
      end

      if evidence.facts.empty?
        update!(sentences: [], promise_assessments: [], generated_at: nil, evidence_digest: evidence.digest)
        return
      end
      if ((sentences + promise_assessments).flat_map { |row| row.fetch("facts") } - evidence.fact_keys).any?
        update!(sentences: [], promise_assessments: [], generated_at: nil, evidence_digest: nil)
      end
    end

    result = Ai::OpenAiService.new.summarize_council_term(member, evidence.facts, request_recorder: CouncilProfiles::TermSummaryRequest.new(self, cycle, evidence, authorized_run: authorized_run))
    publish_response!(result, evidence, cycle)
  end

  def publish_response!(result, evidence, cycle)
    rows = validated_sentences(result, evidence)
    promises = CouncilProfiles::PromiseFollowThrough.from_response(result, evidence, member)
    with_lock do
      update!(sentences: rows, promise_assessments: promises, generated_at: Time.current, evidence_digest: evidence.digest) if attempted_cycle == cycle
    end
  end

  private

  def refresh_citations(rows, facts)
    rows.each do |row|
      row["sources"] = row.fetch("facts").flat_map { |key| facts.fetch(key).fetch(:sources) }.uniq.as_json
    end
  end

  def validated_sentences(result, evidence)
    facts = evidence.facts
    rows = result.fetch("sentences")
    raise ArgumentError, "Invalid term summary length" unless rows.is_a?(Array) && rows.size.between?(1, 4)
    rows.map do |row|
      text = row.fetch("text")
      ids = row.fetch("evidence")
      unless text.is_a?(String) && text.strip.length.between?(12, 360) && ids.is_a?(Array) && ids.size.between?(1, 8) &&
          ids.all? { |id| id.is_a?(Integer) && id.between?(1, facts.size) }
        raise ArgumentError, "Invalid term summary citation"
      end
      { text: text.strip, facts: ids.uniq.map { |id| evidence.fact_keys.fetch(id - 1) }, sources: ids.flat_map { |id| facts.fetch(id - 1).fetch(:sources) }.uniq }
    end
  end
end
