module Campaigns
  class PublishStatements
    VALIDATION_METHOD = "article_passage_and_existing_identity_v1".freeze

    def self.call(extraction)
      return unless extraction.status == "completed"

      extraction.with_lock do
        sequence = 0
        extraction.data.fetch("participants").each do |participant|
          member, identity_exception = resolve_person(participant["name"])
          participant.fetch("answers").each do |answer|
            answer.fetch("statements").each do |statement|
              exception = identity_exception || statement_exception(statement, answer, extraction.campaign_source_version.body)
              record = extraction.campaign_statements.find_or_initialize_by(sequence: sequence)
              data = statement.slice("kind", "summary", "supporting_quote", "conditions", "timeframe", "location").merge(
                "source_name" => participant["name"], "question" => answer["question"])
              attributes = { member_id: member&.id, status: exception ? "unresolved" : "accepted",
                exception: exception, validation_method: VALIDATION_METHOD }
              if record.new_record? || attributes.any? { |key, value| record.public_send(key) != value }
                record.data = data if record.new_record?
                record.assign_attributes(attributes)
                record.validated_at = Time.current
                record.save!
              end
              sequence += 1
            end
          end
        end
      end
    end

    def self.resolve_person(name)
      normalized = Member.normalize_name(name)
      return [ nil, "unknown_person" ] if normalized.blank?

      ids = Member.where("LOWER(name) = LOWER(?)", normalized).pluck(:id) +
        MemberAlias.where("LOWER(name) = LOWER(?)", normalized).pluck(:member_id)
      ids.uniq!
      return [ nil, ids.empty? ? "unknown_person" : "ambiguous_person" ] unless ids.one?

      [ Member.find(ids.sole), nil ]
    end
    private_class_method :resolve_person

    def self.statement_exception(statement, answer, source_text)
      return statement["exception"].presence || "unresolved_source_passage" unless statement["location_status"] == "located"
      return "invalid_statement" unless CampaignStatement::KINDS.key?(statement["kind"]) &&
        %w[summary supporting_quote].all? { |field| statement[field].is_a?(String) && statement[field].present? } &&
        %w[conditions timeframe].all? { |field| statement[field].nil? || statement[field].is_a?(String) }
      return "unresolved_question" unless answer["question"].is_a?(String) && answer["question"].present? && source_text.include?(answer["question"])

      location = statement["location"]
      unless location.is_a?(Hash) && %w[start end].all? { |key| location[key].is_a?(Integer) && location[key] >= 0 } &&
          source_text[location["start"]...location["end"]] == statement["supporting_quote"]
        "unresolved_source_passage"
      end
    end
    private_class_method :statement_exception
  end
end
