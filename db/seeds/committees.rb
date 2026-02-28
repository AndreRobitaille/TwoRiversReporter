# Seed committees and boards for Two Rivers, WI

committees_data = [
  {
    name: "City Council",
    description: "Exercises all legislative and general ordinance powers under Wisconsin's council-manager form of government. Sets policy; the city manager handles execution.",
    committee_type: "city",
    status: "active",
    aliases: ["City Council Meeting", "City Council Work Session", "City Council Special Meeting", "City Council Listening Session"]
  },
  {
    name: "Advisory Recreation Board",
    description: "Recommends improvements to city parks and recreational programs.",
    committee_type: "city",
    status: "active",
    aliases: ["Advisory Recreation Board Meeting", "ARB"]
  },
  {
    name: "Board of Appeals",
    description: "Reviews appeals of official enforcement decisions, handles requests for exceptions to local ordinances, and can approve limited variances.",
    committee_type: "city",
    status: "active",
    aliases: ["Board of Appeals Meeting"]
  },
  {
    name: "Board of Canvassers",
    description: "Checks, confirms, and officially certifies election results.",
    committee_type: "city",
    status: "active",
    aliases: ["Board of Canvassers Meeting"]
  },
  {
    name: "Board of Education",
    description: "State-jurisdiction board overseeing public schools. Not under city control. Sets educational policies, manages district budget, hires superintendent.",
    committee_type: "external",
    status: "active",
    aliases: ["Board of Education Meeting"]
  },
  {
    name: "Branding and Marketing Committee",
    description: "Advises on community branding and marketing strategies for residential, commercial, industrial, and tourism promotion.",
    committee_type: "city",
    status: "dormant",
    aliases: ["Branding and Marketing Committee Meeting"]
  },
  {
    name: "Business and Industrial Development Committee",
    description: "Advises on industrial development, promotes the city's industrial advantages, and recommends use of city properties for industrial purposes. Same membership as CDA; meets concurrently.",
    committee_type: "city",
    status: "active",
    aliases: ["Business and Industrial Development Committee Meeting", "BIDC", "BIDC Meeting", "Business and Industrial Development Committee - Community Development Authority Meeting"]
  },
  {
    name: "Business Improvement District Board",
    description: "Works to retain, expand, and attract businesses of all sizes to Two Rivers.",
    committee_type: "city",
    status: "active",
    aliases: ["Business Improvement District Board Meeting", "BID Board", "BID Board Meeting"]
  },
  {
    name: "Central Park West 365 Planning Committee",
    description: "Planned a centrally located public space on Washington Street/STH 42 with splash pad and ice rink. Originally the Splash Pad and Ice Rink Planning Committee. Mission complete.",
    committee_type: "city",
    status: "dissolved",
    aliases: [
      "Central Park West 365 Planning Committee Meeting",
      "Splash Pad and Ice Rink Planning Committee",
      "Splash Pad and Ice Rink Planning Committee Meeting"
    ]
  },
  {
    name: "Commission for Equal Opportunities in Housing",
    description: "Enforces Fair Housing Act and related laws to ensure equal access to housing without discrimination.",
    committee_type: "city",
    status: "dormant",
    aliases: ["Commission for Equal Opportunities in Housing Meeting"]
  },
  {
    name: "Committee on Aging",
    description: "Identifies concerns of older citizens and advises the Advisory Recreation Board and city manager on senior citizen issues. Primarily an update/input committee.",
    committee_type: "city",
    status: "active",
    aliases: ["Committee on Aging Meeting", "Committee On Aging"]
  },
  {
    name: "Community Development Authority",
    description: "Leads blight elimination, urban renewal, and housing/redevelopment projects. Acts as the city's redevelopment agent. Same membership as BIDC; meets concurrently.",
    committee_type: "city",
    status: "active",
    aliases: ["Community Development Authority Meeting", "CDA", "CDA Meeting"]
  },
  {
    name: "Environmental Advisory Board",
    description: "Advises the public works committee on environmental protection, sustainability, and resiliency policies.",
    committee_type: "city",
    status: "active",
    aliases: ["Environmental Advisory Board Meeting", "EAB", "EAB Meeting"]
  },
  {
    name: "Explore Two Rivers Board of Directors",
    description: "Nonprofit promoting overnight tourism. Operates using room tax revenues in compliance with Wisconsin tourism promotion laws. Funded through Room Tax Commission allocations.",
    committee_type: "tax_funded_nonprofit",
    status: "active",
    aliases: ["Explore Two Rivers Board of Directors Meeting", "Explore Two Rivers Meeting", "Explore Two Rivers Meeting of the Board of Directors"]
  },
  {
    name: "Library Board of Trustees",
    description: "Oversees public library management and policy. Has exclusive control over library funds, property, and staffing including appointing the library director.",
    committee_type: "city",
    status: "active",
    aliases: ["Library Board of Trustees Meeting", "Library Board Meeting"]
  },
  {
    name: "Main Street Board of Directors",
    description: "Nonprofit funded through Business Improvement District special assessments. Manages downtown facade improvements, streetscaping, events, and business support.",
    committee_type: "tax_funded_nonprofit",
    status: "active",
    aliases: ["Main Street Board of Directors Meeting", "Main Street Board Meeting"]
  },
  {
    name: "Personnel and Finance Committee",
    description: "Oversees city personnel policies and financial matters including budgets, salaries, and fiscal management.",
    committee_type: "city",
    status: "active",
    aliases: ["Personnel and Finance Committee Meeting"]
  },
  {
    name: "Plan Commission",
    description: "Develops the city's comprehensive plan for physical development. Reviews and recommends on public buildings, land acquisitions, plats, and zoning matters.",
    committee_type: "city",
    status: "active",
    aliases: ["Plan Commission Meeting"]
  },
  {
    name: "Police and Fire Commission",
    description: "Oversees appointment, promotion, discipline, and dismissal of Police and Fire Chiefs and subordinates.",
    committee_type: "city",
    status: "active",
    aliases: ["Police and Fire Commission Meeting", "PFC", "PFC Meeting"]
  },
  {
    name: "Public Utilities Committee",
    description: "Provides oversight on city utility operations including water, sewer, and electricity.",
    committee_type: "city",
    status: "active",
    aliases: ["Public Utilities Committee Meeting"]
  },
  {
    name: "Public Works Committee",
    description: "Reviews and advises on infrastructure projects, city facility maintenance, and public works operations including roads, drainage, and sanitation.",
    committee_type: "city",
    status: "active",
    aliases: ["Public Works Committee Meeting"]
  },
  {
    name: "Room Tax Commission",
    description: "Manages and allocates room tax revenues from lodging facilities. At least 70% must fund tourism; remainder available for other city needs.",
    committee_type: "city",
    status: "active",
    aliases: ["Room Tax Commission Meeting", "Room Tax Commission Special Meeting"]
  },
  {
    name: "Two Rivers Business Association",
    description: "Nonprofit supporting business growth on the Lakeshore. Provides networking, fosters community, and raises public awareness. Not a city government board.",
    committee_type: "external",
    status: "active",
    aliases: ["Two Rivers Business Association Meeting", "TRBA", "TRBA Meeting"]
  },
  {
    name: "Zoning Board",
    description: "Reviews zoning appeals, special exceptions, and variances. Handles cases where property owners seek relief from zoning ordinance requirements.",
    committee_type: "city",
    status: "active",
    aliases: ["Zoning Board Meeting", "Zoning Board of Appeals", "Zoning Board of Appeals Meeting"]
  }
]

committees_data.each do |data|
  aliases = data.delete(:aliases) || []

  committee = Committee.find_or_create_by!(name: data[:name]) do |c|
    c.assign_attributes(data)
  end

  aliases.each do |alias_name|
    CommitteeAlias.find_or_create_by!(name: alias_name) do |a|
      a.committee = committee
    end
  end
end

Rails.logger.info "Seeded #{Committee.count} committees with #{CommitteeAlias.count} aliases."
