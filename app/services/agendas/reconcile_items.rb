require "digest"
require "set"

module Agendas
  class ReconcileItems
    class AmbiguousMatchError < StandardError; end
    class UnsafeUnmatchedAgendaItemError < StandardError; end

    Result = Struct.new(:noop?, keyword_init: true)

    attr_reader :meeting, :candidates

    def self.digest_for_candidates(candidates)
      Digest::SHA256.hexdigest(candidates.map { |candidate| digest_payload(candidate) }.join("|"))
    end

    def self.digest_payload(candidate)
      [
        candidate[:number],
        candidate[:title],
        candidate[:kind],
        candidate[:order_index],
        candidate[:summary],
        candidate[:recommended_action],
        Array(candidate[:linked_documents]).sort,
        candidate[:parent_key].is_a?(Hash) ? candidate[:parent_key].slice(:number, :title, :kind) : candidate[:parent_key]
      ].to_json
    end

    def initialize(meeting:, candidates:)
      @meeting = meeting
      @candidates = candidates
      @noop = false
    end

    def noop?
      @noop
    end

    def call
      digest = self.class.digest_for_candidates(candidates)
      if meeting.agenda_structure_digest == digest && meeting.agenda_items.exists?
        @noop = true
        return Result.new(noop?: true)
      end

      meeting.transaction do
        mapping = {}
        matched_ids = []

        candidates.each do |candidate|
          parent_id = resolve_parent_id(mapping, candidate[:parent_key])
          matched = find_matching_items(candidate, parent_id)

          agenda_item = if matched.one?
            item = matched.first
            item.update!(
              number: candidate[:number],
              title: candidate[:title],
              kind: candidate[:kind],
              parent_id: parent_id,
              summary: candidate[:summary],
              recommended_action: candidate[:recommended_action],
              order_index: candidate[:order_index]
            )
            item
          elsif matched.empty?
            meeting.agenda_items.create!(
              number: candidate[:number],
              title: candidate[:title],
              kind: candidate[:kind],
              parent_id: parent_id,
              summary: candidate[:summary],
              recommended_action: candidate[:recommended_action],
              order_index: candidate[:order_index]
            )
          else
            raise AmbiguousMatchError, "multiple agenda items match #{candidate.inspect}"
          end

          mapping[candidate_key(candidate)] = agenda_item.id
          matched_ids << agenda_item.id
        end

        stale_items = meeting.agenda_items.where.not(id: matched_ids)
        stale_ids = stale_items.pluck(:id).to_set

        stale_items
          .select { |agenda_item| agenda_item.parent_id.nil? || !stale_ids.include?(agenda_item.parent_id) }
          .each { |agenda_item| destroy_stale_subtree!(agenda_item, stale_ids) }

        meeting.update!(agenda_structure_digest: digest)
      end
      Result.new(noop?: false)
    end

    def resolve_parent_id(mapping, parent_key)
      return nil if parent_key.blank?

      return mapping.fetch(parent_key) if parent_key.is_a?(Hash) && mapping.key?(parent_key)

      if parent_key.is_a?(String)
        number, title = parent_key.split(":", 2)
        return meeting.agenda_items.find_by(number: number, title: title)&.id if number.present? && title.present?
      end

      nil
    end

    private

    def find_matching_items(candidate, parent_id)
      kind = candidate[:kind].presence || "item"
      scope = meeting.agenda_items.where(number: candidate[:number])
      scope = kind == "item" ? scope.where(kind: [nil, "item"]) : scope.where(kind: [nil, "section"])

      exact_parent = scope.where(parent_id: parent_id)
      if exact_parent.many?
        raise AmbiguousMatchError, "multiple agenda items match #{candidate.inspect}"
      end

      if exact_parent.one?
        matched = exact_parent.first
        if parent_id.present? && matched.kind.present? && matched.title != candidate[:title]
          raise AmbiguousMatchError, "multiple agenda items match #{candidate.inspect}"
        end

        return exact_parent if parent_id.present? || matched.kind.present?
      end

      legacy_flat = scope.where(parent_id: nil)
      raise AmbiguousMatchError, "multiple agenda items match #{candidate.inspect}" if legacy_flat.many?

      if legacy_flat.one?
        only_legacy = legacy_flat.first
        return legacy_flat if only_legacy.title == candidate[:title] && only_legacy.order_index == candidate[:order_index]
        return legacy_flat if only_legacy.title == candidate[:title]
        return scope.none
      end

      scope.none
    end

    def candidate_key(candidate)
      candidate.slice(:number, :title, :kind, :parent_key)
    end

    def ensure_safe_to_remove!(agenda_item)
      return if agenda_item.motions.none? && agenda_item.topics.none? && agenda_item.meeting_documents.none? && TopicAppearance.where(agenda_item_id: agenda_item.id).none?

      raise UnsafeUnmatchedAgendaItemError, "refusing to remove stale agenda item #{agenda_item.id} with downstream references"
    end

    def destroy_stale_subtree!(agenda_item, stale_ids)
      ensure_safe_to_remove!(agenda_item)

      agenda_item.children.each do |child|
        next if stale_ids.include?(child.id)

        raise UnsafeUnmatchedAgendaItemError, "refusing to remove stale agenda item #{agenda_item.id} with non-stale descendants"
      end

      agenda_item.children.select { |child| stale_ids.include?(child.id) }.each do |child|
        destroy_stale_subtree!(child, stale_ids)
      end

      agenda_item.destroy!
    end
  end
end
