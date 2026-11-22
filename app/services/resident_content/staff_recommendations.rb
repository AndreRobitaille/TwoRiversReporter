module ResidentContent
  # The first comparison boundary requires the complete unchanged proposal text.
  # Alternative/amended wording stays unresolved rather than guessing polarity.
  class StaffRecommendations
    def initialize(member, period:)
      @member, @period = member, period
    end

    def groups
      @groups ||= begin
        periods = @period.selected ? [ @period.selected ] : @period.selectable
        inventories = periods.filter_map { |period| CouncilAttendance.new(@member, period: period).call }
        ids = inventories.flat_map { |inventory| inventory.fetch(:meeting_ids) }.uniq
        @motions = Motion.where(meeting_id: ids).includes(:meeting, :votes, agenda_item: :parent).order(id: :desc).to_a
        vote_bearing = @motions.select { |motion| motion.votes.any? }.map(&:meeting_id).uniq
        @duplicate_ids = inventories.flat_map { |inventory| inventory.fetch(:rows) }
          .select { |row| (row.fetch(:meeting_ids) & vote_bearing).size > 1 }.flat_map { |row| row.fetch(:meeting_ids) }
        @by_item = @motions.group_by(&:agenda_item_id)
        evidence = CouncilIssueReview.where(status: "completed")
          .joins(:meeting_document).where(meeting_documents: { meeting_id: ids })
          .where("jsonb_array_length(council_issue_reviews.data->'recommendations') > 0")
          .includes(meeting_document: :meeting).flat_map do |stage|
          citation = stage.current_citation
          next [] unless citation
          stage.data.fetch("recommendations").map do |recommendation|
            { evidence: recommendation, citation: citation, meeting: stage.meeting_document.meeting,
              title: stage.context.fetch("agenda").find { |item| item["id"] == recommendation["agenda_item_id"] }&.fetch("title") }
          end
        end
        evidence.group_by { |entry| author_key(entry.fetch(:evidence)) }.map do |key, entries|
          rows = entries.group_by { |entry| entry.dig(:evidence, "agenda_item_id") }.flat_map do |item_id, item_entries|
            comparisons_for(item_id, item_entries)
          end
          rows.sort_by! { |row| [ row[:motion]&.meeting&.starts_at || row[:sources].first.fetch(:meeting).starts_at, row[:motion]&.id || 0 ] }.reverse!
          included = rows.reject { |row| row[:excluded] }
          divided = included.select { |row| row[:divided] }
          author = entries.first.fetch(:evidence).slice("author", "role", "author_kind")
          { key: key, author: author, rows: rows, supported: included.count { |row| row[:supported] }, compared: included.size,
            divided_supported: divided.count { |row| row[:supported] }, divided_compared: divided.size }
        end.sort_by { |group| group.dig(:author, "author").downcase }
      end
    end

    def missing_count
      groups
      covered = groups.flat_map { |group| group[:rows].filter_map { |row| row[:motion]&.id } }
      @motions.count { |motion| substantive?(motion) && !covered.include?(motion.id) }
    end

    private

    def comparisons_for(item_id, entries)
      motions = @by_item.fetch(item_id, [])
      return [ { motion: nil, sources: entries, excluded: "No matching recorded decision", divided: false } ] if motions.empty?

      signatures = entries.map { |entry| [ entry.dig(:evidence, "position"), normalize(entry.dig(:evidence, "proposal")) ] }.uniq
      motions.map do |motion|
        vote = motion.votes.find { |ballot| ballot.member_id == @member.id }
        timely = entries.find do |entry|
          recommendation = entry.fetch(:evidence)
          recommendation["timing"] == "before_vote" && recommendation["made_on"] &&
            Date.iso8601(recommendation["made_on"]) <= motion.meeting.starts_at.to_date
        end
        excluded = if @duplicate_ids.include?(motion.meeting_id)
          "Votes appear on multiple meeting copies"
        elsif !substantive?(motion)
          "Routine procedural motion"
        elsif motions.size > 1
          "Multiple motions or amendments need review"
        elsif signatures.size > 1
          "Conflicting recommendations or proposal versions"
        elsif !timely
          "Recommendation timing is unclear or after the decision"
        elsif entries.any? { |entry| entry.dig(:evidence, "conditions").present? }
          "Additional recommendation conditions need review"
        elsif normalize(timely.dig(:evidence, "proposal")) != normalize(motion.description)
          "Proposal wording differs from the recorded motion"
        elsif !vote&.value.in?(%w[yes no]) || vote.evidence_basis == "attendance_derived"
          "No independently recorded yes/no vote"
        end
        values = motion.votes.map(&:value)
        supported = excluded.nil? && (vote.value == (timely.dig(:evidence, "position") == "support" ? "yes" : "no"))
        { motion: motion, sources: entries, own: vote&.value, excluded: excluded, supported: supported,
          divided: values.include?("yes") && values.include?("no") }
      end
    end

    def author_key(evidence)
      CouncilProfiles::ReserveAiSpend.request_digest(evidence.slice("author", "role", "author_kind").transform_values { |value| normalize(value) })
    end

    def normalize(value)
      value.to_s.split.join(" ").downcase
    end

    def substantive?(motion)
      @profile ||= OfficialProfile.new(@member)
      @profile.substantive_motion?(motion)
    end
  end
end
