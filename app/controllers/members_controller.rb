class MembersController < ApplicationController
  allow_unauthenticated_access

  # Motion descriptions that are procedural — filter from "Other Votes"
  PROCEDURAL_PATTERNS = ResidentContent::OfficialProfile::PROCEDURAL_PATTERNS

  def show
    @member = Member.find(params[:id])

    @memberships = @member.committee_memberships
      .where(ended_on: nil)
      .where("role IS NULL OR role NOT IN (?)", %w[staff non_voting])
      .includes(:committee)
      .sort_by { |cm| [ cm.committee.name == "City Council" ? 0 : 1, cm.committee.name ] }
    @current_position = @member.primary_current_position
    @service_periods = @member.council_service_periods.newest_first
      .includes(start_source_version: { file_attachment: :blob }, end_source_version: { file_attachment: :blob })

    @attendance = load_attendance
    @campaign_statements = CampaignStatement.current_for(@member) unless gated_for_visitor?

    @topic_groups, @other_votes = ResidentContent::OfficialProfile.new(@member).vote_groups
  end

  private

  def load_attendance
    ResidentContent::OfficialProfile.new(@member).attendance
  end
end
