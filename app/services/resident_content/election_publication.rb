module ResidentContent
  class ElectionPublication
    def self.current
      Current.election_publication ||= new
    end

    def initialize
      @results = CouncilElectionResult.confirmed_by(Date.current)
      @losses = @results.transform_values { |r| r.candidate_names - r.winner_names }
    end

    def withdrawn?(date, name)
      @losses.fetch(date, []).include?(name)
    end

    def withdrawn_dates(names)
      @losses.filter_map { |date, field| date if field.intersect?(names) }
    end

    def public_members
      Member.where.not(id: hidden_member_ids)
    end

    def withdrawn_portrait?(portrait)
      private_names.include?(portrait.name) || private_member_ids.include?(portrait.member_id)
    end

    private

    def visible_names
      @visible_names ||= begin
        # A later filing reopens the person’s profile. The losing campaign stays closed.
        live = CouncilElectionCandidateList.where.not(election_on: @results.keys).pluck(:names).flatten
        live.concat(@results.values.flat_map(&:winner_names))
        historical = Campaigns::ElectionBackfill::EDITIONS[Date.current.year.to_s]
        live.concat(historical.fetch("candidates")) if historical && !@results.key?(Date.iso8601(historical.fetch("election_on")))
        live.uniq
      end
    end

    def private_names
      @private_names ||= @losses.values.flatten.uniq - visible_names
    end

    def private_member_ids
      @private_member_ids ||= begin
        matches = CouncilElection.member_ids_by_name(private_names | visible_names)
        matches.values_at(*private_names).compact - matches.values_at(*visible_names)
      end
    end

    def hidden_member_ids
      @hidden_member_ids ||= begin
        ids = private_member_ids
        service = [ CouncilServicePeriod, MemberPosition, CommitteeMembership, Vote,
          MeetingAttendance.where.not(attendee_type: "guest") ]
        service.each { |records| ids -= records.where(member_id: ids).distinct.pluck(:member_id) if ids.any? }
        ids
      end
    end
  end
end
