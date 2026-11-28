class CouncilCandidatesController < ApplicationController
  allow_unauthenticated_access

  def show
    @date = Campaigns::ElectionBackfill.election_on(params[:year])
    @name = params[:name]
    raise ActiveRecord::RecordNotFound unless @date && Campaigns::ElectionBackfill.candidates_on(@date).include?(@name)

    raise ActiveRecord::RecordNotFound if ResidentContent::ElectionPublication.current.withdrawn?(@date, @name)
    return redirect_to committee_path("city-council", anchor: "spring-election") if gated_for_visitor?

    member_id = ResidentContent::CouncilElection.member_ids_by_name([ @name ])[@name]
    return redirect_to member_path(member_id) if member_id

    profile = ResidentContent::CandidateProfile.new([ @name ], through: @date)
    @candidate_campaigns = profile.campaigns
    @civic_connections = profile.connections
    @portrait = CandidatePortrait.current_for(@name => nil)[@name]
    @list_source = ResidentContent::CouncilElection.for_year(@date.year)&.candidates&.fetch(@name, nil)
  end
end
