module ResidentContent
  # A profile finding follows the current evidence for one person in one election.
  class CandidateCampaign
    attr_reader :year, :name, :events

    def initialize(year, name, events, field)
      @year = year
      @name = name
      @events = events
      @field = field
    end

    def spoken_and_written_answers?
      events.any? { |e| e.forum && e.statuses[name] == "Spoke at forum" } &&
        events.any? { |e| !e.forum && e.statuses[name] == "Answered" }
    end

    def missed_forums_and_surveys?
      forums, surveys = events.partition(&:forum)
      forums.any? && surveys.any? && forums.all? { |e| e.statuses[name] == "Did not participate" } &&
        surveys.all? { |e| e.statuses[name] == "Did not answer" }
    end

    def account(previous: nil)
      forums, surveys = events.partition(&:forum)
      actions = [
        forum_action("spoke at", forums, "Spoke at forum"),
        forum_action("missed", forums, "Did not participate"),
        survey_action("answered", surveys, "Answered"),
        survey_action("did not answer", surveys, "Did not answer")
      ].compact
      surname = name.split.last
      text = "In #{year}, #{surname} #{actions.to_sentence}."
      return text unless missed_forums_and_surveys?

      opponents = @field.count do |candidate|
        forums.all? { |e| e.statuses[candidate] == "Spoke at forum" } && surveys.all? { |e| e.statuses[candidate] == "Answered" }
      end
      if opponents.positive?
        count = %w[zero one two three four five].fetch(opponents, opponents.to_s)
        text += " #{count.capitalize} #{"opponent".pluralize(opponents)} gave voters both spoken and written answers."
      end
      if previous
        text + " Voters looking back at #{surname}’s #{previous.year} forum and questionnaire answers had no way to tell from these sources whether those priorities still held."
      else
        text + " Voters weighing #{surname}’s plans had to look beyond these sources."
      end
    end

    private

    def forum_action(verb, forums, status)
      selected = forums.select { |event| event.statuses[name] == status }
      return if selected.empty?

      label = if selected.size == forums.size
        case selected.size
        when 1 then "the recorded candidate forum"
        when 2 then "both recorded candidate forums"
        else "all #{selected.size} recorded candidate forums"
        end
      else
        selected.map { |event| "the #{event.date.strftime('%B %-d')} forum" }.to_sentence
      end
      "#{verb} #{label}"
    end

    def survey_action(verb, surveys, status)
      publishers = surveys.select { |event| event.statuses[name] == status }.map do |event|
        event.name.match?(/Herald Times Reporter|\AHTR\z/i) ? "the Herald Times Reporter" : event.name
      end.uniq
      return if publishers.empty?

      if publishers.one?
        "#{verb} the #{publishers.first.delete_prefix('the ')} questionnaire"
      else
        "#{verb} questionnaires from #{publishers.to_sentence}"
      end
    end
  end
end
