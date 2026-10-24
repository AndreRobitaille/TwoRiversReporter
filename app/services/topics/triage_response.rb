module Topics
  class TriageResponse
    Invalid = Class.new(StandardError)
    FIELDS = {
      "merge_map" => { "canonical" => "string", "aliases" => "array", "confidence" => "number", "rationale" => "string" },
      "approvals" => { "topic" => "string", "approve" => "boolean", "confidence" => "number", "rationale" => "string" },
      "blocks" => { "topic" => "string", "block" => "boolean", "confidence" => "number", "rationale" => "string" }
    }.freeze

    def self.response_format
      properties = FIELDS.to_h do |key, fields|
        entry_properties = fields.to_h do |name, type|
          definition = { type: type }
          definition.merge!(items: { type: "string" }, minItems: 1) if type == "array"
          definition.merge!(minimum: 0, maximum: 1) if name == "confidence"
          definition[:enum] = [ true ] if type == "boolean"
          [ name, definition ]
        end
        [ key, { type: "array", description: "Zero or more decisions; include every confident decision once.",
          items: { type: "object", properties: entry_properties, required: fields.keys, additionalProperties: false } } ]
      end
      { type: "json_schema", json_schema: { name: "topic_triage", strict: true,
        schema: { type: "object", properties: properties, required: FIELDS.keys, additionalProperties: false } } }
    end

    def self.parse(response)
      result = JSON.parse(response)
      raise Invalid, "Expected exactly merge_map, approvals, and blocks" unless result.is_a?(Hash) && result.keys.sort == FIELDS.keys.sort

      FIELDS.each do |key, fields|
        entries = result.fetch(key)
        raise Invalid, "#{key} must be an array" unless entries.is_a?(Array)

        entries.each do |entry|
          raise Invalid, "Invalid #{key} entry fields" unless entry.is_a?(Hash) && entry.keys.sort == fields.keys.sort

          fields.each do |name, type|
            value = entry.fetch(name)
            valid = case type
            when "string" then value.is_a?(String) && value.present?
            when "array" then value.is_a?(Array) && value.any? && value.all? { |item| item.is_a?(String) && item.present? }
            when "number" then value.is_a?(Numeric) && value.between?(0, 1)
            when "boolean" then value == true
            end
            raise Invalid, "Invalid #{key}.#{name}" unless valid
          end
        end
      end
      result
    end
  end
end
