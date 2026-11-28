module Campaigns
  class FilingCandidateReader
    COUNTS = %w[zero one two three four five six seven eight nine ten].freeze
    FIELD_SIZE = /\b(\d+|#{COUNTS.join("|")}) (?:people running|candidates? (?:are running|have filed|filed|will (?:run|appear)))\b/i
    ROSTER = /\A(?:This includes (?:sitting council members )?|(?:The )?candidates (?:are|include)\s*:?\s*)(.+)\z/i
    NAME_PART = /(?:\p{Lu}[\p{L}’'-]*|\p{Lu}\.)/
    NAME = /\A#{NAME_PART}(?: #{NAME_PART}){1,3}\z/

    def self.names(html)
      doc = Nokogiri::HTML5(html, nil, "UTF-8")
      root = doc.at_css("article .entry-content, article .gnt_ar_b") || doc.at_css("article")
      return unless root
      return unless root.text.squish.match?(/\b(?:fil(?:ed|ing)|paperwork|ballots? .*?set)\b/i)

      section = two_rivers_section(root)
      text = section.join(" ")
      return unless text.match?(/\b(?:city council|council (?:members?|seats?))\b/i)

      count = text[FIELD_SIZE, 1]&.downcase
      return unless count

      rosters = section.filter_map { |line| line[ROSTER, 1] }
      return unless rosters.one?

      entries = rosters.first.delete_suffix(".").split(/,? who will be challenged by |,?\s+and |,\s*/i)
      names = entries.map { |entry| entry.strip.sub(/\A(?:Council (?:Vice[- ]President|President)|incumbent) /i, "") }
      size = COUNTS.index(count) || count.to_i
      names if names.size == size && names.uniq(&:downcase).size == size && names.all? { |name| NAME.match?(name) }
    end

    def self.two_rivers_section(root)
      blocks = root.css("h2,h3,p").to_a
      start = blocks.index { |node| node.text.squish.match?(/\A(?:In Two Rivers,|Two Rivers City Council\b)/i) }
      return [] unless start

      section = [ blocks[start].text.squish ]
      blocks.drop(start + 1).each do |node|
        line = node.text.squish
        break if node.name != "p" || line.match?(/\A(?:As for|In (?!Two Rivers)|Meanwhile|Turning to)\b|\b(?:school board|board of education)\b/i)
        section << line
      end
      section
    end
    private_class_method :two_rivers_section
  end
end
