module CanonicalRosters
  class Parser
    Error = Class.new(StandardError)

    private

    def entry(name:, source_name: name, membership_role: nil, membership_title: nil, position_kind: nil, position_title: nil)
      Entry.new(
        name: name,
        source_name: source_name,
        membership_role: membership_role,
        membership_title: membership_title,
        position_kind: position_kind,
        position_title: position_title
      )
    end

    def validate_unique_entries!(entries, expected: nil, minimum: nil)
      names = entries.map(&:name)
      raise Error, "No roster entries found" if entries.empty?
      raise Error, "Expected #{expected} entries, found #{entries.size}" if expected && entries.size != expected
      raise Error, "Expected at least #{minimum} entries, found #{entries.size}" if minimum && entries.size < minimum
      raise Error, "Roster contains duplicate names" if names.uniq.size != names.size

      entries
    end
  end
end
