module ResidentContent
  class CandidateProfile
    CONNECTIONS = YAML.safe_load_file(Rails.root.join("config/council_civic_connections.yml")).freeze

    attr_reader :connections

    def initialize(names, through: nil)
      identities = names.map(&:downcase).to_set
      @connections = CONNECTIONS.select { |note| note.fetch("people").any? { |person| identities.include?(person.downcase) } }
      @editions = ElectionParticipation.editions.filter_map do |date, field|
        next if through && date > through

        name = field.find { |candidate| identities.include?(candidate.downcase) }
        [ date, name ] if name && !ElectionPublication.current.withdrawn?(date, name)
      end
    end

    def latest_entry
      @editions.first
    end

    def campaigns
      @campaigns ||= @editions.filter_map do |date, name|
        ElectionParticipation.new(date).campaign_for(name)
      end
    end
  end
end
