class CouncilTermSummary < ApplicationRecord
  belongs_to :member

  def complete_for?(digest)
    evidence_digest == digest && promise_assessments.none? { |finding| finding["status"] == "pending_review" }
  end

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
      changed_sources = ((sentences + promise_assessments).flat_map { |row| row.fetch("facts") } - evidence.fact_keys).any?
      city_evidence = evidence.facts.any? { |f| f[:city_outcome] } || promise_assessments.any? { |row| %w[city_result city_progress].include?(row["status"]) }
      if evidence.selection_review && evidence.tracked? && promise_assessments.any? && (changed_sources || city_evidence)
        retain_current_findings!(evidence)
      elsif changed_sources
        update!(sentences: [], promise_assessments: [], generated_at: nil, evidence_digest: nil)
      end
    end

    service = Ai::OpenAiService.new(request_timeout: Ai::OpenAiService::CAMPAIGN_ANALYSIS_TIMEOUT)
    result = service.summarize_council_term(member, evidence.facts, request_recorder: CouncilProfiles::TermSummaryRequest.new(self, cycle, evidence, authorized_run: authorized_run))
    publish_response!(result, evidence, cycle)
  end

  def publish_response!(result, evidence, cycle)
    raise ArgumentError, "Invalid promise list" unless result["promises"].is_a?(Array)
    promises = CouncilProfiles::PromiseFollowThrough.for_publication(result, evidence, member)
    rows = if promises.any? { |finding| finding.fetch("status") == "pending_review" }
      evidence.sourced_overview(result.fetch("sentences"))
    else
      validated_sentences(result, evidence)
    end
    with_lock do
      update!(sentences: rows, promise_assessments: promises, generated_at: Time.current, evidence_digest: evidence.digest) if attempted_cycle == cycle
    end
  end

  def apply_city_outcomes!(evidence)
    groups = CouncilProfiles::PromiseFollowThrough.position_groups(evidence.facts)
    with_lock do
      updated = promise_assessments.deep_dup
      groups.each do |group|
        position = evidence.facts.fetch(group.first - 1)
        words = position.fetch(:promise_words).pluck("supporting_quote")
        rows = updated.select { |row| row["heading"] == position[:position] && words.include?(row["quote"]) }
        city = CouncilProfiles::PromiseFollowThrough.city_finding(group, evidence)
        if city
          next unless rows.all? { |row| CouncilProfiles::PromiseFollowThrough.city_updates?(row["status"]) }
          updated -= rows
          updated << city
        else
          rows.select { |row| %w[city_progress city_result].include?(row["status"]) }.each do |row|
            row.delete("outcome_quote")
            row.delete("member_step")
            row.merge!("status" => "pending_review", "reason" => "The Council record for this position is awaiting assessment.",
              "sources" => position.fetch(:sources), "facts" => group.map { |id| evidence.fact_keys.fetch(id - 1) })
          end
        end
      end
      update!(promise_assessments: updated, evidence_digest: nil) if updated.as_json != promise_assessments
    end
  end

  private

  # A new selection can retire campaign facts before funding is available for
  # another weekly assessment. Keep only verdicts whose full evidence survives.
  def retain_current_findings!(evidence)
    pending = CouncilProfiles::PromiseFollowThrough.for_publication({ "promises" => [] }, evidence, member)
    keys = evidence.fact_keys
    retained = pending.map do |item|
      previous = promise_assessments.find do |row|
        row["heading"] == item["heading"] && row["quote"] == item["quote"] &&
          (item.fetch("facts") - row.fetch("facts")).empty? && (row.fetch("facts") - keys).empty?
      end
      next item unless previous
      next item if %w[city_result city_progress].include?(previous["status"])
      next item if %w[city_result city_progress].include?(item["status"]) && CouncilProfiles::PromiseFollowThrough.city_updates?(previous["status"])
      previous
    end
    refresh_citations(retained, keys.zip(evidence.facts).to_h)
    update!(sentences: evidence.sourced_overview([]), promise_assessments: retained, evidence_digest: nil)
  end

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
