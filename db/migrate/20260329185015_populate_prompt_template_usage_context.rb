class PopulatePromptTemplateUsageContext < ActiveRecord::Migration[8.1]
  def up
    usage_contexts = {
      "analyze_meeting_content" => "Meeting page: the editorial summary paragraph at the top, the bullet-point highlights below it, the public input section, and the per-agenda-item cards with vote badges",
      "render_meeting_summary" => "Meeting page: the full-text recap section on older meetings that don't have structured data (fallback for pre-2026 meetings)",
      "extract_topics" => "Pipeline: decides which topics get linked to each agenda item. Those topics appear as pills on meeting pages and as entries on the topics index",
      "refine_catchall_topic" => "Pipeline: when an agenda item falls under a generic ordinance heading (e.g. \"Height and Area Exceptions\"), this re-names it to something specific. Affects the topic name residents see",
      "re_extract_item_topics" => "Pipeline: re-runs topic extraction when an admin splits a broad topic. Affects which topics agenda items link to",
      "extract_votes" => "Meeting page: the motion text and pass/fail/tabled vote badges on each agenda item card",
      "extract_committee_members" => "Members page: who attended each meeting, their role (voting/staff/guest), and whether they were present, absent, or excused",
      "triage_topics" => "Pipeline: auto-approves or blocks proposed topics after extraction. Blocked topics never appear on the site; approved topics become visible",
      "analyze_topic_summary" => "Topic page: the per-meeting snapshot in \"The Story\" section — what happened with this topic at a specific meeting",
      "render_topic_summary" => "Topic page: turns the structured per-meeting analysis into editorial prose (legacy pass 2, used for older summaries)",
      "analyze_topic_briefing" => "Topic page: \"What to Watch\" callout, \"The Story\" narrative, and the \"Record\" timeline. Homepage: the \"What Happened\" and \"Coming Up\" headline cards",
      "render_topic_briefing" => "Topic page: turns the structured briefing analysis into editorial and factual-record prose (pass 2, used for older briefings)",
      "generate_briefing_interim" => "Homepage: quick headline text on the \"What Happened\" and \"Coming Up\" cards when a full briefing hasn't been generated yet",
      "generate_topic_description_detailed" => "Everywhere topics appear: the one-line description under each topic name on cards, lists, and pills (for topics with 3+ agenda items)",
      "generate_topic_description_broad" => "Everywhere topics appear: the one-line description under each topic name on cards, lists, and pills (for topics with fewer than 3 agenda items)"
    }

    usage_contexts.each do |key, context|
      execute "UPDATE prompt_templates SET usage_context = #{connection.quote(context)} WHERE key = #{connection.quote(key)}"
    end
  end

  def down
    execute "UPDATE prompt_templates SET usage_context = NULL"
  end
end
