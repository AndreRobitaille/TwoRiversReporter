class CommitteesController < ApplicationController
  COMMITTEE_TYPE_ORDER = { "city" => 0, "tax_funded_nonprofit" => 1, "external" => 2 }.freeze
  COMMITTEE_TYPE_LABELS = {
    "city" => [ "City Government", "Elected and appointed bodies that make binding decisions for Two Rivers" ],
    "tax_funded_nonprofit" => [ "Tax-Funded Organizations", "Non-profit boards that receive city funding but operate independently" ],
    "external" => [ "Other Organizations", "Independent bodies not directly controlled by the city" ]
  }.freeze

  def index
    committees = Committee.where(status: %w[active dormant])
                          .includes(committee_memberships: :member)

    @committees = committees.sort_by do |c|
      [
        c.name == "City Council" ? 0 : 1,
        COMMITTEE_TYPE_ORDER[c.committee_type] || 99,
        c.name
      ]
    end

    @member_counts = @committees.each_with_object({}) do |c, counts|
      counts[c.id] = c.committee_memberships.count { |cm| cm.ended_on.nil? && !%w[staff non_voting].include?(cm.role) }
    end
  end

  def show
    @committee = Committee.find_by!(slug: params[:slug])

    @memberships = @committee.committee_memberships
      .where(ended_on: nil)
      .where.not(role: %w[staff non_voting])
      .includes(:member)

    city_council = Committee.find_by(name: "City Council")
    @council_member_ids = if city_council && city_council.id != @committee.id
      city_council.committee_memberships
        .where(ended_on: nil)
        .where.not(role: %w[staff non_voting])
        .pluck(:member_id)
        .to_set
    else
      Set.new
    end

    @recent_topics = load_recent_topics
  end

  private

  def load_recent_topics
    Topic.approved
      .joins(agenda_item_topics: { agenda_item: :meeting })
      .where(meetings: { committee_id: @committee.id })
      .select("topics.*, MAX(meetings.starts_at) AS latest_meeting_date")
      .group("topics.id")
      .order("latest_meeting_date DESC")
      .limit(8)
  end
end
