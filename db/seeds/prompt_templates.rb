# db/seeds/prompt_templates.rb
#
# Seeds the 15 AI prompt templates with metadata, then populates them with
# real prompt text via the prompt_templates:populate rake task.
# Idempotent — skips existing keys, populate updates in place.

PROMPT_TEMPLATES_DATA = [
  {
    key: "extract_votes",
    name: "Vote Extraction",
    description: "Extracts motions and vote records from meeting minutes",
    usage_context: "Meeting page: the motion text and pass/fail/tabled vote badges on each agenda item card",
    model_tier: "default",
    placeholders: [
      { "name" => "text", "description" => "Meeting minutes text (truncated to 50k chars)" },
      { "name" => "agenda_items", "description" => "Numbered agenda items for the meeting (for motion-to-item linking)" }
    ]
  },
  {
    key: "extract_committee_members",
    name: "Committee Member Extraction",
    description: "Extracts roll call and attendance from meeting minutes",
    usage_context: "Members page: who attended each meeting, their role (voting/staff/guest), and whether they were present, absent, or excused",
    model_tier: "lightweight",
    placeholders: [
      { "name" => "text", "description" => "Meeting minutes text (truncated to 50k chars)" }
    ]
  },
  {
    key: "extract_topics",
    name: "Topic Extraction",
    description: "Classifies agenda items into civic topics",
    usage_context: "Pipeline: decides which topics get linked to each agenda item. Those topics appear as pills on meeting pages and as entries on the topics index",
    model_tier: "default",
    placeholders: [
      { "name" => "existing_topics", "description" => "All approved topic names" },
      { "name" => "community_context", "description" => "Knowledge base context" },
      { "name" => "meeting_documents_context", "description" => "Extracted text from meeting documents" },
      { "name" => "items_text", "description" => "Formatted agenda items to classify" }
    ]
  },
  {
    key: "refine_catchall_topic",
    name: "Catchall Topic Refinement",
    description: "Refines broad ordinance topics into specific civic concerns",
    usage_context: "Pipeline: when an agenda item falls under a generic ordinance heading (e.g. \"Height and Area Exceptions\"), this re-names it to something specific. Affects the topic name residents see",
    model_tier: "default",
    placeholders: [
      { "name" => "item_title", "description" => "Agenda item title" },
      { "name" => "item_summary", "description" => "Agenda item summary" },
      { "name" => "catchall_topic", "description" => "The broad topic being refined" },
      { "name" => "document_text", "description" => "Related document text (6k truncated)" },
      { "name" => "existing_topics", "description" => "All approved topic names" }
    ]
  },
  {
    key: "re_extract_item_topics",
    name: "Topic Re-extraction",
    description: "Re-extracts topics when splitting a broad topic",
    usage_context: "Pipeline: re-runs topic extraction when an admin splits a broad topic. Affects which topics agenda items link to",
    model_tier: "default",
    placeholders: [
      { "name" => "item_title", "description" => "Agenda item title" },
      { "name" => "item_summary", "description" => "Agenda item summary" },
      { "name" => "document_text", "description" => "Related document text (6k truncated)" },
      { "name" => "broad_topic_name", "description" => "The broad topic being split" },
      { "name" => "existing_topics", "description" => "All approved topic names" }
    ]
  },
  {
    key: "triage_topics",
    name: "Topic Triage",
    description: "AI-assisted approval, blocking, and merging of proposed topics",
    usage_context: "Pipeline: auto-approves or blocks proposed topics after extraction. Blocked topics never appear on the site; approved topics become visible",
    model_tier: "default",
    placeholders: [
      { "name" => "context_json", "description" => "JSON with topic data, similarities, and community context" }
    ]
  },
  {
    key: "analyze_topic_summary",
    name: "Topic Summary Analysis",
    description: "Structured analysis of a topic's activity in a single meeting",
    usage_context: "Topic page: the per-meeting snapshot in \"The Story\" section — what happened with this topic at a specific meeting",
    model_tier: "default",
    placeholders: [
      { "name" => "committee_context", "description" => "Active committees and descriptions" },
      { "name" => "context_json", "description" => "Topic context JSON with meeting data" }
    ]
  },
  {
    key: "render_topic_summary",
    name: "Topic Summary Rendering",
    description: "Renders structured topic analysis into editorial prose",
    usage_context: "Topic page: turns the structured per-meeting analysis into editorial prose (legacy pass 2, used for older summaries)",
    model_tier: "default",
    placeholders: [
      { "name" => "plan_json", "description" => "Structured analysis JSON from pass 1" }
    ]
  },
  {
    key: "analyze_topic_briefing",
    name: "Topic Briefing Analysis",
    description: "Rolling briefing — structured analysis across all meetings for a topic",
    usage_context: "Topic page: \"What to Watch\" callout, \"The Story\" narrative, and the \"Record\" timeline. Homepage: the \"What Happened\" and \"Coming Up\" headline cards",
    model_tier: "default",
    placeholders: [
      { "name" => "committee_context", "description" => "Active committees and descriptions" },
      { "name" => "context", "description" => "Topic briefing context with all meeting data" }
    ]
  },
  {
    key: "render_topic_briefing",
    name: "Topic Briefing Rendering",
    description: "Renders briefing analysis into editorial content",
    usage_context: "Topic page: turns the structured briefing analysis into editorial and factual-record prose (pass 2, used for older briefings)",
    model_tier: "default",
    placeholders: [
      { "name" => "analysis_json", "description" => "Structured briefing analysis JSON from pass 1" }
    ]
  },
  {
    key: "generate_briefing_interim",
    name: "Interim Briefing",
    description: "Quick headline generation for newly approved topics",
    usage_context: "Homepage: quick headline text on the \"What Happened\" and \"Coming Up\" cards when a full briefing hasn't been generated yet",
    model_tier: "lightweight",
    placeholders: [
      { "name" => "topic_name", "description" => "Name of the topic" },
      { "name" => "current_headline", "description" => "Current headline if any" },
      { "name" => "meeting_body", "description" => "Committee/body name" },
      { "name" => "meeting_date", "description" => "Meeting date" },
      { "name" => "agenda_items", "description" => "Related agenda items" }
    ]
  },
  {
    key: "generate_topic_description_detailed",
    name: "Topic Description (Detailed)",
    description: "Generates scope descriptions for topics with 3+ agenda items",
    usage_context: "Everywhere topics appear: the one-line description under each topic name on cards, lists, and pills (for topics with 3+ agenda items)",
    model_tier: "lightweight",
    placeholders: [
      { "name" => "topic_name", "description" => "Name of the topic" },
      { "name" => "activity_text", "description" => "Formatted agenda item activity" },
      { "name" => "headlines_text", "description" => "Recent headlines if any" }
    ]
  },
  {
    key: "generate_topic_description_broad",
    name: "Topic Description (Broad)",
    description: "Generates scope descriptions for topics with fewer than 3 agenda items",
    usage_context: "Everywhere topics appear: the one-line description under each topic name on cards, lists, and pills (for topics with fewer than 3 agenda items)",
    model_tier: "lightweight",
    placeholders: [
      { "name" => "topic_name", "description" => "Name of the topic" },
      { "name" => "activity_text", "description" => "Formatted agenda item activity (may be empty)" },
      { "name" => "headlines_text", "description" => "Recent headlines if any" }
    ]
  },
  {
    key: "analyze_meeting_content",
    name: "Meeting Content Analysis",
    description: "Single-pass structured analysis of full meeting content",
    usage_context: "Meeting page: the editorial summary paragraph at the top, the bullet-point highlights below it, the public input section, and the per-agenda-item cards with vote badges",
    model_tier: "default",
    placeholders: [
      { "name" => "kb_context", "description" => "Knowledge base context chunks" },
      { "name" => "committee_context", "description" => "Active committees and descriptions" },
      { "name" => "type", "description" => "Document type: packet or minutes" },
      { "name" => "body_name", "description" => "Meeting body name (e.g. City Council Meeting)" },
      { "name" => "doc_text", "description" => "Meeting document text (truncated to 50k)" }
    ]
  },
  {
    key: "render_meeting_summary",
    name: "Meeting Summary Rendering",
    description: "Renders meeting analysis into editorial prose (legacy)",
    usage_context: "Meeting page: the full-text recap section on older meetings that don't have structured data (fallback for pre-2026 meetings)",
    model_tier: "default",
    placeholders: [
      { "name" => "plan_json", "description" => "Structured analysis JSON from pass 1" },
      { "name" => "doc_text", "description" => "Original document text for reference" }
    ]
  },
  {
    key: "extract_knowledge",
    name: "Knowledge Extraction",
    description: "Extracts durable civic facts from meeting summaries and raw document text",
    usage_context: "Pipeline: after meeting summarization, identifies institutional knowledge worth remembering — business ownership, relationships, sentiment signals, historical context. Never shown to residents; injected into future AI prompts as background context",
    model_tier: "default",
    placeholders: [
      { "name" => "summary_json", "description" => "Meeting summary generation_data JSON" },
      { "name" => "raw_text", "description" => "Raw meeting document text (truncated to 25k chars)" },
      { "name" => "existing_kb", "description" => "Existing relevant knowledge entries to avoid duplication" }
    ]
  },
  {
    key: "extract_knowledge_patterns",
    name: "Knowledge Pattern Detection",
    description: "Detects cross-meeting patterns from accumulated knowledge entries",
    usage_context: "Pipeline: weekly analysis of accumulated per-meeting knowledge entries to find behavioral patterns, escalation signals, and relationship inferences. Pattern entries are labeled differently in prompts to prevent compounding",
    model_tier: "default",
    placeholders: [
      { "name" => "knowledge_entries", "description" => "All approved extracted + manual knowledge entries" },
      { "name" => "recent_summaries", "description" => "Recent topic briefing data (last 90 days)" },
      { "name" => "topic_metadata", "description" => "Topic appearance counts, lifecycle status, committees" }
    ]
  },
  {
    key: "triage_knowledge",
    name: "Knowledge Triage",
    description: "Auto-approves or blocks proposed knowledge entries",
    usage_context: "Pipeline: evaluates whether extracted knowledge entries are grounded, durable, non-duplicative, and not misreading normal civic process. Blocked entries never enter prompts; approved entries become available for retrieval",
    model_tier: "default",
    placeholders: [
      { "name" => "entries_json", "description" => "Proposed knowledge entries with title, body, reasoning, confidence" },
      { "name" => "existing_kb", "description" => "Existing approved knowledge entries to check for duplicates" }
    ]
  },
  {
    key: "knowledge_search_answer",
    name: "Knowledge Search Answer",
    description: "Synthesizes an answer to admin questions using knowledge base context",
    usage_context: "Admin tool: on-demand Q&A over the knowledge base. Admin types a question, top-10 KB chunks are retrieved by vector similarity, and this prompt synthesizes a prose answer with numbered citations. Not part of the automated pipeline — triggered only by manual admin search",
    model_tier: "default",
    placeholders: [
      { "name" => "context", "description" => "Numbered knowledge base chunks with origin labels" },
      { "name" => "question", "description" => "The admin's search query" }
    ]
  }
].freeze

puts "Seeding prompt templates..."

PROMPT_TEMPLATES_DATA.each do |data|
  data = data.dup
  placeholders = data.delete(:placeholders)
  usage_context = data.delete(:usage_context)
  existing = PromptTemplate.find_by(key: data[:key])

  if existing
    puts "  PromptTemplate '#{data[:key]}' already exists, skipping."
    next
  end

  template = PromptTemplate.create!(
    **data,
    placeholders: placeholders,
    usage_context: usage_context,
    system_role: "TODO: Copy from OpenAiService heredoc via admin UI at /admin/prompt_templates",
    instructions: "TODO: Copy from OpenAiService heredoc via admin UI at /admin/prompt_templates"
  )
  puts "  Created PromptTemplate '#{data[:key]}' (ID: #{template.id})"
end

puts "Done. #{PromptTemplate.count} prompt templates in database."

# Populate with real prompt text from the populate rake task data
puts "Populating prompt text..."
Rake::Task["prompt_templates:populate"].invoke
