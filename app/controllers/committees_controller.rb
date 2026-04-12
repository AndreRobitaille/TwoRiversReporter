class CommitteesController < ApplicationController
  # Governance groupings matching the committee connections diagram.
  # These are stable for a small city — if a new committee is created,
  # add it here. Unmatched committees fall into :advisory by default.
  SUBCOMMITTEES = [
    "Public Works Committee",
    "Personnel and Finance Committee",
    "Public Utilities Committee"
  ].freeze

  STANDALONE = [
    "Police and Fire Commission",
    "Library Board of Trustees",
    "Zoning Board",
    "Board of Appeals",
    "Board of Canvassers"
  ].freeze

  # Committees to exclude from the public index (no data, not city-run)
  EXCLUDED = [
    "Board of Education",
    "Two Rivers Business Association"
  ].freeze

  # Short descriptions for index cards — one sentence, no links, written for scanning.
  # Full descriptions with statute links live on show pages.
  CARD_DESCRIPTIONS = {
    "City Council" => "The legislative body of Two Rivers. Sets tax levies, approves budgets, and makes final decisions on zoning, development, and city policy.",
    "Public Works Committee" => "Roads, drainage, sanitation, and city infrastructure.",
    "Personnel and Finance Committee" => "City personnel policies, budgets, and salaries.",
    "Public Utilities Committee" => "Water, sewer, and electrical services.",
    "Plan Commission" => "Reviews zoning changes and development proposals before they reach Council.",
    "Environmental Advisory Board" => "Advises on environmental policy, conservation, and sustainability.",
    "Committee on Aging" => "Advocates for the needs and well-being of older residents.",
    "Advisory Recreation Board" => "Recommends improvements for city parks and recreational programs.",
    "Room Tax Commission" => "Allocates hotel tax revenue for tourism and community events.",
    "Business and Industrial Development Committee" => "Advises on business development and industrial growth.",
    "Business Improvement District Board" => "Supports downtown business retention, expansion, and recruitment.",
    "Community Development Authority" => "Leads housing, blight remediation, and neighborhood development.",
    "Police and Fire Commission" => "Hires, promotes, and disciplines police and fire chiefs and officers.",
    "Library Board of Trustees" => "Governs the public library's policies, budget, and operations.",
    "Zoning Board" => "Hears zoning appeals and grants variances from the city code.",
    "Board of Appeals" => "Reviews appeals of decisions made by city officials.",
    "Board of Canvassers" => "Certifies election results.",
    "Explore Two Rivers Board of Directors" => "Promotes tourism and travel using city room tax funds.",
    "Main Street Board of Directors" => "Funded through the BID to support downtown revitalization."
  }.freeze

  GOVERNANCE_SECTIONS = [
    { key: :subcommittees, label: "Council Subcommittees",
      description: "These report directly to Council. Their members are all elected council members." },
    { key: :advisory, label: "Advisory Boards",
      description: "Appointed boards that advise Council on specific areas. Recommendations aren't binding — Council makes the final call." },
    { key: :standalone, label: "Independent Authority",
      description: "These bodies have their own legal authority — they don't just advise Council." },
    { key: :nonprofit, label: "Tax-Funded Nonprofits",
      description: "Independent boards that receive city tax funding but set their own agendas." }
  ].freeze

  def index
    all = Committee.where(status: %w[active dormant])
                   .includes(committee_memberships: :member)

    @council = all.find { |c| c.name == "City Council" }

    @member_counts = all.each_with_object({}) do |c, counts|
      counts[c.id] = c.committee_memberships.count { |cm| cm.ended_on.nil? && !%w[staff non_voting].include?(cm.role) }
    end

    # Group into governance categories
    groups = { subcommittees: [], advisory: [], standalone: [], nonprofit: [] }
    all.reject { |c| c.name == "City Council" || EXCLUDED.include?(c.name) }
       .reject { |c| c.status == "dormant" && @member_counts[c.id] == 0 }
       .sort_by(&:name)
       .each do |c|
      bucket = if SUBCOMMITTEES.include?(c.name)
        :subcommittees
      elsif STANDALONE.include?(c.name)
        :standalone
      elsif c.committee_type == "tax_funded_nonprofit"
        :nonprofit
      else
        :advisory
      end
      groups[bucket] << c
    end
    @governance_groups = groups
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
