class MembersController < ApplicationController
  COMMITTEE_TYPE_ORDER = { "city" => 0, "tax_funded_nonprofit" => 1, "external" => 2 }.freeze

  def index
    @committees = Committee
      .joins(:committee_memberships)
      .merge(CommitteeMembership.current)
      .where.not(committee_memberships: { role: %w[staff non_voting] })
      .distinct
      .includes(committee_memberships: :member)
      .sort_by { |c| [ c.name == "City Council" ? 0 : 1, COMMITTEE_TYPE_ORDER[c.committee_type] || 99, c.name ] }

    city_council = @committees.find { |c| c.name == "City Council" }
    @council_member_ids = if city_council
      city_council.committee_memberships
        .select { |cm| cm.ended_on.nil? && !%w[staff non_voting].include?(cm.role) }
        .map(&:member_id)
        .to_set
    else
      Set.new
    end

    @city_manager_id = MeetingAttendance.where(capacity: "City Manager").pick(:member_id)

    @committee_topics = load_committee_topics
  end

  def show
    @member = Member.find(params[:id])
    @votes = @member.votes.joins(motion: :meeting).includes(motion: :meeting).order("meetings.starts_at DESC")
  end

  private

  def load_committee_topics
    committee_ids = @committees.map(&:id)
    rows = Topic.approved
      .joins(agenda_item_topics: { agenda_item: :meeting })
      .where(meetings: { committee_id: committee_ids })
      .select("topics.*, meetings.committee_id AS assoc_committee_id")
      .order("topics.last_activity_at DESC NULLS LAST")

    result = Hash.new { |h, k| h[k] = [] }
    seen = Hash.new { |h, k| h[k] = Set.new }
    rows.each do |topic|
      cid = topic[:assoc_committee_id]
      next if seen[cid].include?(topic.id)

      seen[cid] << topic.id
      result[cid] << topic if result[cid].size < 5
    end
    result
  end
end
