class MembersController < ApplicationController
  allow_unauthenticated_access

  before_action :load_profile, only: %i[show record campaign issues]

  def show
    load_election_context unless gated_for_visitor?
    if !gated_for_visitor? && @current_position&.kind == "city_council" && @record_period.selected
      @term_summary = CouncilTermSummary.find_by(member: @member, term_started_on: @record_period.selected.started_on)
    end
    if @candidate_role && !@has_election_profile && !@former_committee && @service_periods.empty? &&
        params.slice(:term, :votes, :page, :q, :topic, :body, :split, :kind, :statement, :decision).empty?
      return show_challenger
    end
    summary_profile = !gated_for_visitor? && (@council_profile || @term_summary&.sentences.present?)
    if summary_profile && params[:statement].present?
      load_campaign_comparisons
      return render :campaign
    end

    # Older vote searches, term selections and pagination still open the record.
    if summary_profile && params.slice(:term, :votes, :page, :q, :topic, :body, :split, :kind).empty?
      if params[:decision].present?
        @linked_vote = @member.votes.includes(motion: [ :meeting, :agenda_item, :votes ]).find_by(motion_id: params[:decision])
      end
      if @term_summary&.sentences.present?
        entries = @term_summary.sentences + @term_summary.promise_assessments
        urls = entries.flat_map { |item| item.fetch("sources").pluck("url") }.uniq
        @campaign_source_urls = CampaignSourceVersion.where(source_url: urls).distinct.pluck(:source_url).to_set
        if @record_period.selected.period_key == "#{@term_summary.term_started_on.year}-election"
          reviewed = CampaignPlatformReview.where(member: @member,
            election_on: @term_summary.term_started_on.beginning_of_year..@term_summary.term_started_on).maximum(:election_on)
          if reviewed
            records = campaign_statements.select { |row| row.campaign_source_version.election_on == reviewed }
            @campaign_source_urls.merge(records.map { |row| row.campaign_source_version.source_url })
            platform = ResidentContent::CampaignPlatform.new(records, include_council_records: false)
            @term_summary = CouncilProfiles::ReviewedPlatformReport.new(@term_summary, platform, @campaign_source_urls)
          end
        end
      else
        load_campaign_preview
      end
      @answer_reviews = ResidentContent::ReviewedCampaignAnswers.for(@member).select do |review|
        @record_period.selected&.period_key == "#{review.fetch("source_record").election_on.year}-election"
      end
      @council_attendance = council_attendance if @record_period.selected
      return render :election_profile
    end

    @separate_record = summary_profile
    load_record
  end

  def record
    @separate_record = true
    if params[:votes] == "all"
      unless gated_for_visitor?
        ids = ResidentContent::CouncilAttendance.new(@member, period: @record_period.selected).meeting_ids if @record_period.selected
        load_votes(ResidentContent::OfficialProfile.new(@member, council_meeting_ids: ids))
      end
      return render :vote_search
    end
    load_record
    render :show
  end

  def campaign
    if withdrawn_campaign_dates.any? && ResidentContent::CandidateProfile.new(member_names).latest_entry.nil? && campaign_statements.empty?
      raise ActiveRecord::RecordNotFound
    end
    return if gated_for_visitor?

    load_election_context
    @answer_reviews = ResidentContent::ReviewedCampaignAnswers.for(@member)
    load_campaign_comparisons
  end

  def issues
    return if gated_for_visitor?

    @council_attendance = council_attendance
    @pagy, @issue_updates = pagy(:offset, issue_updates, limit: 25)
  end

  def compare
    @member = ResidentContent::ElectionPublication.current.public_members.find(params[:id])
    @peer = ResidentContent::ElectionPublication.current.public_members.find(params[:peer_id])
    raise ActiveRecord::RecordNotFound if @peer == @member
    @record_period = ResidentContent::CouncilPeriod.new(@member, key: params[:term])
    @show_divided = params[:subset] == "divided"
    unless gated_for_visitor?
      attendance = ResidentContent::CouncilAttendance.new(@member, period: @record_period.selected).call
      @comparison = ResidentContent::PeerVotes.new(@member, attendance: attendance).compare(@peer)
      rows = @comparison.fetch(:rows).select { |row| row.fetch(:excluded).nil? && (!@show_divided || row.fetch(:divided)) }
      @pagy, @comparison_rows = pagy(:offset, rows, limit: 25)
    end
    respond_to { |format| format.html }
  end

  def recommendations
    @member = ResidentContent::ElectionPublication.current.public_members.find(params[:id])
    @record_period = ResidentContent::CouncilPeriod.new(@member, key: params[:term])
    @show_divided = params[:subset] == "divided"
    unless gated_for_visitor?
      report = ResidentContent::StaffRecommendations.new(@member, period: @record_period)
      @recommendation_group = report.groups.find { |group| group[:key] == params[:source] } || raise(ActiveRecord::RecordNotFound)
      @missing_recommendations = report.missing_count
      rows = @recommendation_group.fetch(:rows).select { |row| !@show_divided || row[:divided] }
      @pagy, @recommendation_rows = pagy(:offset, rows, limit: 25)
    end
    respond_to { |format| format.html }
  end

  private

  def member_names
    @member_names ||= [ @member.name, *@member.member_aliases.pluck(:name) ]
  end

  def withdrawn_campaign_dates
    @withdrawn_campaign_dates ||= ResidentContent::ElectionPublication.current.withdrawn_dates(member_names)
  end

  def load_election_context
    names = member_names
    profile = ResidentContent::CandidateProfile.new(names)
    @civic_connections = profile.connections
    @candidate_campaigns = profile.campaigns
    if @current_position.nil? && @memberships.empty? && profile.latest_entry
      @date, @listed_name = profile.latest_entry
      @candidate_role = "#{@date.year} City Council candidate"
    end
  end

  def show_challenger
    @name = @member.name
    @list_source = ResidentContent::CouncilElection.for_year(@date.year)&.candidates&.fetch(@listed_name, nil)
    @has_public_record = @member.votes.exists? || @member.meeting_attendances.exists? ||
      @member.member_positions.exists? || @member.committee_memberships.exists?
    load_campaign_comparisons
    render "council_candidates/show"
  end

  def load_profile
    respond_to { |format| format.html }
    @member = ResidentContent::ElectionPublication.current.public_members.find(params[:id])
    @portrait = CandidatePortrait.current_for(@member.name => @member.id)[@member.name]

    @portrait = nil if @portrait && ResidentContent::ElectionPublication.current.withdrawn_portrait?(@portrait)

    memberships = @member.committee_memberships.where("role IS NULL OR role NOT IN (?)", %w[staff non_voting]).includes(:committee)
    @memberships = memberships.current.sort_by { |cm| [ cm.committee.name == "City Council" ? 0 : 1, cm.committee.name ] }
    @current_position = @member.primary_current_position
    @record_period = ResidentContent::CouncilPeriod.new(@member, key: params[:term])
    @service_periods = @record_period.periods
    @record_params = @service_periods.any? || params[:term].present? ? { term: @record_period.key } : {}

    load_election unless gated_for_visitor?
    load_committee_navigation(memberships)
  end

  def load_committee_navigation(memberships)
    committees = @memberships.map(&:committee)
    roster = committees.find { |committee| committee.slug == params[:committee] }
    council_membership = @memberships.find { |membership| membership.committee.name == "City Council" }
    @council_profile = council_membership&.role.present? || @has_election_profile
    council = council_membership&.committee
    council ||= council_committee if @current_position&.kind == "city_council" || @has_election_profile
    @profile_committees = [ roster, council ].compact.uniq
    @profile_committees = committees if committees.one? && @profile_committees.empty?
    if committees.empty? && @profile_committees.empty?
      @former_committee = memberships.where.not(ended_on: nil).order(ended_on: :desc, id: :desc).first&.committee
    end
  end

  def council_committee
    @council_committee ||= @memberships.find { |membership| membership.committee.name == "City Council" }&.committee ||
      Committee.find_by(name: "City Council")
  end

  def load_election
    edition = ResidentContent::CouncilElection.current
    return unless edition
    name = edition.member_ids_by_name.key(@member.id)
    return unless name

    @election = edition
    @election_name = name
    @has_election_profile = edition.terms_ending.key?(name)
    @election_council_slug = council_committee&.slug
  end

  def campaign_statements
    @campaign_statements ||= CampaignStatement.current_for(@member).reject do |row|
      withdrawn_campaign_dates.include?(row.campaign_source_version.election_on)
    end
  end

  def load_campaign_preview
    by_year = campaign_statements.group_by { |statement| statement.campaign_source_version.election_on }
    period = @record_period.selected
    dates = by_year.keys.select { |date| date <= Date.current && (!@election || date < @election.election_on) }
    dates.select! { |date| date.year == period.started_on.year } if period && period.period_key == "#{period.started_on.year}-election"
    @campaign_date = dates.max
    return unless @campaign_date

    platform = ResidentContent::CampaignPlatform.new(by_year.fetch(@campaign_date), include_council_records: false)
    @campaign_preview = platform.items.first(2).map { |item| [ item.fetch(:description), item.fetch(:statements).first ] }
    if @campaign_preview.empty?
      @campaign_preview = platform.unreviewed.reject { |row| row.data["kind"] == "retrospective_claim" }.first(2)
        .map { |row| [ row.data.values_at("summary", "conditions", "timeframe").compact_blank.uniq.join(" "), row ] }
    end
  end

  def council_attendance
    ResidentContent::CouncilAttendance.new(@member, period: @record_period.selected).call
  end

  def issue_updates
    ResidentContent::IssueUpdates.new(@member, attendance: @council_attendance,
      period: @record_period, statements: visible_campaign_statements).call
  end

  def visible_campaign_statements
    @campaign_platforms ||= ResidentContent::CampaignPlatform.by_election(campaign_statements)
    @campaign_platforms.values.flat_map(&:statements)
  end

  def load_campaign_comparisons
    visible = visible_campaign_statements
    if params[:statement].present?
      @selected_statement = visible.find { |statement| statement.id.to_s == params[:statement] }
    end
    return if visible.empty?

    @campaign_issues = ResidentContent::CampaignIssues.new(statements: @campaign_platforms.values.flat_map(&:unreviewed)).call
    @campaign_actions = ResidentContent::CampaignActions.new(@member, statements: @campaign_statements,
      council_attendance: @council_attendance || ResidentContent::CouncilAttendance.new(@member).call).call
    @campaign_issue_evidence = ResidentContent::CampaignIssueEvidence.new(@member, statements: @campaign_statements).call
  end

  def load_record
    @council_attendance = council_attendance
    if @council_attendance && (coverage = SiteSetting.instance.council_coverage).present? &&
        @council_attendance.fetch(:period).started_on.iso8601 == coverage["from"] && @council_attendance.fetch(:period).ended_on.nil?
      @council_coverage = coverage
    end
    meeting_ids = @council_attendance&.fetch(:meeting_ids)
    profile = ResidentContent::OfficialProfile.new(@member,
      council_meeting_ids: (@record_period.selected ? meeting_ids || [] : nil), during: @record_period.range)
    @attendance = profile.recorded_attendance(excluding_committee_id: @council_attendance&.fetch(:committee_id))
    return if gated_for_visitor?

    load_campaign_comparisons unless @separate_record
    @recorded_actions = ResidentContent::RecordedActions.new(@member, period: @record_period).call
    @formal_cases = ResidentContent::FormalCases.new(@member, period: @record_period).call
    @issue_updates = issue_updates unless @separate_record
    @peer_comparisons = ResidentContent::PeerVotes.new(@member, attendance: @council_attendance).summaries
    @staff_recommendations = ResidentContent::StaffRecommendations.new(@member, period: @record_period).groups
    load_votes(profile)
  end

  def load_votes(profile)
    @show_all_votes = params[:votes] == "all"
    @vote_filters = ResidentContent::VoteFilters.new(profile, params: params)
    @record_params.merge!(@vote_filters.query_params)
    filtered_votes = @vote_filters.call(featured: !@show_all_votes)
    if @show_all_votes
      @pagy, @recorded_votes = pagy(:offset, filtered_votes, limit: 25)
      ActiveRecord::Associations::Preloader.new(records: @recorded_votes.map(&:motion), associations: [
        { meeting: :meeting_documents }, { decision_observation: :minutes_extraction }
      ]).call
    else
      @pagy, featured_votes = pagy(:offset, filtered_votes, limit: 25)
      @topic_groups, @other_votes = profile.vote_groups(featured_votes)
    end
  end
end
