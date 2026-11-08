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

    @attendance = load_attendance

    @show_all_votes = params[:votes] == "all"
    profile = ResidentContent::OfficialProfile.new(@member)
    unless gated_for_visitor?
      if @show_all_votes
        @pagy, @recorded_votes = pagy(:offset, profile.votes, limit: 25)
      else
        @pagy, featured_votes = pagy(:offset, profile.resident_votes, limit: 25)
        @topic_groups, @other_votes = profile.vote_groups(featured_votes)
      end
    end
  end

  private

  def load_attendance
    ResidentContent::OfficialProfile.new(@member).attendance
  end
end
