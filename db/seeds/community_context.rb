# Seed Two Rivers community context for AI extraction and triage.
# These KnowledgeSource entries give the AI understanding of what
# matters to Two Rivers residents vs. routine institutional noise.

COMMUNITY_CONTEXT_TITLE = "Two Rivers Community Context — Topic Extraction Guide"

COMMUNITY_CONTEXT_BODY = <<~CONTEXT
  ## Community Identity

  Two Rivers, WI is a small post-industrial city on Lake Michigan with a strong generational identity rooted in its manufacturing heritage (notably Hamilton Industries and Eggers Industries). Many residents have deep, multi-generational ties to the city and significant nostalgia for its industrial past. The community values stability, continuity, and the preservation of neighborhood character.

  ## What Residents Care About (High-Salience Topics)

  The following types of civic issues are likely to be important to Two Rivers residents. When these appear on agendas, they are strong candidates for topic creation:

  - Property tax increases, reassessments, or TIF district changes that affect household budgets
  - Development or zoning changes that alter the physical character of neighborhoods, downtown, or the lakefront
  - The tension between the city's manufacturing heritage and its transition toward a tourism-oriented economy — many residents did not choose and do not want this transition
  - School district decisions, closures, or funding changes
  - Infrastructure decay or major capital projects in established residential areas
  - Changes to Main Street or Washington Street businesses and character
  - Any item generating significant public comment volume — this is the strongest signal of resident concern
  - Decisions where residents feel excluded from the process or believe leadership is not listening
  - Narrow or divided votes on the council — these signal community disagreement
  - Items where it matters who benefits from a decision (developer interests vs. resident interests)
  - Historic preservation or demolition of landmarks
  - Utility rates, water/sewer infrastructure, and service reliability

  ## What Is Routine (Low-Salience / Not Topic-Worthy)

  The following types of items appear on agendas regularly but are typically routine institutional business, not persistent civic concerns. They should generally NOT become topics:

  - Standard license renewals for existing businesses (liquor, operator, etc.) with no controversy
  - Individual personnel actions (hiring, retirement) unless they affect a key leadership position
  - Routine budget approvals or line-item transfers with no tax impact
  - Procedural committee business (setting meeting dates, approving prior minutes)
  - Proclamations, ceremonial recognitions, and awards
  - Consent agenda items that are truly routine (not bundled controversial items)
  - Standard vendor contract renewals at similar terms
  - Routine report acceptances (monthly financial reports, department updates)

  ## Resident Disposition

  Two Rivers residents tend to:
  - Be skeptical of city leadership, both elected officials and appointed staff
  - Feel that decisions are often made before public input is genuinely considered
  - Pay close attention to who benefits from development and spending decisions
  - Value stability and preservation over growth and change
  - Have strong opinions about downtown character and lakefront use
  - Engage most actively when proposed changes affect their neighborhoods directly

  ## Signals of Resident Importance

  When evaluating whether a civic issue matters to residents, weight these signals:
  - Volume and intensity of public comment on an agenda item (strongest signal)
  - Items that change the physical, economic, or social character of the community
  - Divided or contentious votes (signal the community is not aligned)
  - Issues where institutional framing ("economic development", "revitalization") may not match resident priorities
  - Long-running disputes or concerns that residents keep raising
  - Items where transparency or process complaints arise
CONTEXT

existing = KnowledgeSource.find_by(title: COMMUNITY_CONTEXT_TITLE)
if existing
  puts "Community context KnowledgeSource already exists (ID: #{existing.id}), skipping."
else
  source = KnowledgeSource.create!(
    title: COMMUNITY_CONTEXT_TITLE,
    source_type: "note",
    body: COMMUNITY_CONTEXT_BODY,
    active: true,
    verification_notes: "Seeded from design discussion about Two Rivers resident values and concerns."
  )
  puts "Created community context KnowledgeSource (ID: #{source.id})."
  puts "Run IngestKnowledgeSourceJob.perform_now(#{source.id}) to generate embeddings."
end
