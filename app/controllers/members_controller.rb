class MembersController < ApplicationController
  allow_unauthenticated_access

  def show
    @member = Member.find(params[:id])

    @memberships = @member.committee_memberships
      .where(ended_on: nil)
      .where("role IS NULL OR role NOT IN (?)", %w[staff non_voting])
      .includes(:committee)
      .sort_by { |cm| [ cm.committee.name == "City Council" ? 0 : 1, cm.committee.name ] }
    @current_position = @member.primary_current_position
    @record_period = ResidentContent::CouncilPeriod.new(@member, key: params[:term])
    @service_periods = @record_period.periods
    @record_params = @service_periods.any? || params[:term].present? ? { term: @record_period.key } : {}

    @council_attendance = ResidentContent::CouncilAttendance.new(@member, period: @record_period.selected).call
    meeting_ids = @council_attendance&.fetch(:meeting_ids)
    profile = ResidentContent::OfficialProfile.new(@member,
      council_meeting_ids: (@record_period.selected ? meeting_ids || [] : nil), during: @record_period.range)
    @attendance = profile.recorded_attendance(excluding_committee_id: @council_attendance&.fetch(:committee_id))
    @campaign_statements = CampaignStatement.current_for(@member) unless gated_for_visitor?
    if @campaign_statements&.any?
      @campaign_issues = ResidentContent::CampaignIssues.new(statements: @campaign_statements).call
      @campaign_actions = ResidentContent::CampaignActions.new(@member, statements: @campaign_statements,
        council_attendance: @council_attendance || ResidentContent::CouncilAttendance.new(@member).call).call
    end

    @show_all_votes = params[:votes] == "all"
    unless gated_for_visitor?
      @issue_updates = ResidentContent::IssueUpdates.new(@member, attendance: @council_attendance,
        period: @record_period, statements: @campaign_statements || []).call
      @peer_comparisons = ResidentContent::PeerVotes.new(@member, attendance: @council_attendance).summaries
      @vote_filters = ResidentContent::VoteFilters.new(profile, params: params)
      @record_params.merge!(@vote_filters.query_params)
      filtered_votes = @vote_filters.call(featured: !@show_all_votes)
      if @show_all_votes
        @pagy, @recorded_votes = pagy(:offset, filtered_votes, limit: 25)
      else
        @pagy, featured_votes = pagy(:offset, filtered_votes, limit: 25)
        @topic_groups, @other_votes = profile.vote_groups(featured_votes)
      end
    end
  end

  def compare
    @member = Member.find(params[:id])
    @peer = Member.find(params[:peer_id])
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
end
