module CouncilProfiles
  class TermResponse
    def self.format
      ids = { type: "array", items: { type: "integer" } }
      sentence = object(text: { type: "string" }, evidence: ids.merge(minItems: 1, maxItems: 8))
      finding = object(
        positions: ids.merge(minItems: 1), status: { type: "string", enum: PromiseFollowThrough::LABELS.keys },
        reason: { type: "string" }, record: ids.merge(maxItems: 4),
        material_effect: { type: [ "string", "null" ], enum: PromiseFollowThrough::MATERIAL_EFFECTS + [ nil ] },
        attribution: { type: [ "string", "null" ], description: "Exact wording naming the member's action, or the verified outcome_quote for a city finding." })
      { type: "json_schema", json_schema: { name: "council_term", strict: true, schema: object(
        sentences: { type: "array", minItems: 1, maxItems: 4, items: sentence },
        promises: { type: "array", items: finding }) } }
    end

    def self.object(properties)
      { type: "object", properties: properties, required: properties.keys, additionalProperties: false }
    end
    private_class_method :object
  end
end
