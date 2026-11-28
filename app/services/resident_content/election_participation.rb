module ResidentContent
  class ElectionParticipation
    Event = Data.define(:date, :name, :forum, :statuses, :sources) do
      def speakers
        statuses.select { |_name, status| status == "Spoke at forum" }.keys
      end

      def absences
        statuses.select { |_name, status| status == "Did not participate" }.keys
      end

      def source_for(candidate)
        sources[candidate] || sources.fetch(:event)
      end
    end

    NONRESPONSE = /\A(?:did not (?:answer|respond)|no response)(?: by (?:the )?deadline)?[.!]?\z/i
    # The saved project includes a full copy of the captions. Public pages only need verified names.
    SPEAKERS = Arel.sql(%q{CASE WHEN prepared_transcript->>'speaker_attribution_verified' = 'true' THEN jsonb_path_query_array(prepared_transcript, '$.segments[*] ? (@.attribution == "reviewer_verified").speaker') END})

    def self.editions
      dates = CampaignSource.distinct.pluck(:election_on) | CouncilElectionCandidateList.pluck(:election_on)
      dates.sort.reverse_each.filter_map do |date|
        names = Campaigns::ElectionBackfill.candidates_on(date)
        [ date, names ] if names.any?
      end.to_h
    end

    attr_reader :names, :events

    def initialize(date)
      @year = date.year
      @names = Campaigns::ElectionBackfill.candidates_on(date)
      edition = Campaigns::ElectionBackfill.for(date.year)
      leads = (edition&.fetch("sources") || {}).values
      @leads = leads.index_by { |lead| lead.fetch("url") }
      leads.each { |lead| @leads[lead["original_url"]] = lead if lead["original_url"] }
      sources = CampaignSource.where(election_on: date).order(:published_on, :id)
      @forums = {}
      @events = []
      sources.pluck(:publisher, :published_on, :source_url, :coverage, :title, :confirmed_absences, SPEAKERS,
        Arel.sql("CASE WHEN coverage <> 'full_transcript' THEN body END")).each do |publisher, day, url, coverage, title, absent, speakers, body|
        if coverage == "full_transcript"
          add_recording(publisher, day, url, absent, speakers)
        elsif @leads.dig(url, "kind") == "article" || title.match?(/questionnaire|candidate survey/i)
          @events << questionnaire(publisher, day, url, body)
        end
      end
    end

    def campaign_for(name)
      return unless names.include?(name) && events.any? { |event| event.statuses.key?(name) }

      CandidateCampaign.new(@year, name, events, names)
    end

    def forum_for(source)
      @forums.fetch([ source.published_on, source.publisher.downcase ])
    end

    private

    def add_recording(publisher, day, url, absent, speakers)
      key = [ day, publisher.downcase ]
      event = @forums.fetch(key) do
        recording = Event.new(day, publisher, true, {}, { event: url })
        @events << recording
        @forums[key] = recording
      end
      (@names & absent).each do |name|
        next if event.statuses[name] == "Spoke at forum"

        event.statuses[name] = "Did not participate"
        event.sources[name] = url
      end
      (@names & Array(speakers)).each do |name|
        event.statuses[name] = "Spoke at forum"
        event.sources[name] = url
      end
    end

    def questionnaire(publisher, day, url, body)
      statuses = {}
      lines = body.lines.map(&:strip).compact_blank
      lines.slice_before { |line| @names.include?(line) }.each do |name, *lines_for_name|
        next unless @names.include?(name) && lines_for_name.any?

        if lines_for_name.one? && NONRESPONSE.match?(lines_for_name.first)
          statuses[name] = "Did not answer"
        elsif !NONRESPONSE.match?(lines_for_name.first) && questionnaire_answer?(lines_for_name, @leads[url])
          statuses[name] = "Answered"
        end
      end
      Event.new(day, publisher, false, statuses, { event: url })
    end

    def questionnaire_answer?(lines, lead)
      questions = Array(lead&.dig("questions")) + Array(lead&.dig("response_question"))
      questions = lines.select { |line| line.end_with?("?") } if questions.empty?
      if questions.any?
        return lines.each_cons(2).any? { |question, answer| questions.include?(question) && !questions.include?(answer) && !NONRESPONSE.match?(answer) }
      end

      lines.any? { |line| line.match?(/\b(?:I|my|we|our)\b/i) && !line.end_with?("?") }
    end
  end
end
