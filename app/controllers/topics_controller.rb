class TopicsController < ApplicationController
  include HighlightSignals

  def index
    active_scope = Topic.publicly_visible
                        .active
                        .joins(:agenda_items)
                        .group("topics.id")
                        .select("topics.*, COUNT(agenda_items.id) as agenda_item_count_cache")

    # Hero: high-impact active topics with recent activity (30 days), ranked by impact
    @hero_topics = active_scope
                     .where(last_activity_at: 30.days.ago..)
                     .order(Arel.sql("resident_impact_score DESC NULLS LAST"), last_activity_at: :desc)
                     .limit(6)

    # Main list: remaining active topics, excluding hero, paginated
    hero_ids = @hero_topics.map(&:id)
    remaining_scope = active_scope
                        .where.not(id: hero_ids)
                        .order(last_activity_at: :desc)

    @pagy, @topics = pagy(:offset, remaining_scope, limit: 20)

    # Preload briefings to avoid N+1 on cards
    ActiveRecord::Associations::Preloader.new(
      records: @hero_topics + @topics,
      associations: :topic_briefing
    ).call

    # Highlight signals for all visible topics
    visible_ids = (hero_ids + @topics.map(&:id)).uniq
    @highlight_signals = build_highlight_signals(visible_ids)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def explore
  end

  def show
    @topic = Topic.publicly_visible.find(params[:id])

    # Upcoming: future meetings where this topic is on the agenda.
    # Deduplicate on (meeting_id, agenda_item_id) as a view-layer safety net;
    # paired with the unique DB index idx_topic_appearances_unique_triple and
    # the model-level uniqueness validation on TopicAppearance.
    @upcoming = @topic.topic_appearances
                      .includes(meeting: [], agenda_item: [])
                      .joins(:meeting)
                      .where("meetings.starts_at > ?", Time.current)
                      .order("meetings.starts_at ASC")
                      .uniq { |a| [ a.meeting_id, a.agenda_item_id ] }

    @briefing = @topic.topic_briefing

    # Key decisions: all motions linked to this topic's agenda items
    @decisions = Motion.joins(agenda_item: :agenda_item_topics)
                       .where(agenda_item_topics: { topic_id: @topic.id })
                       .includes(:meeting, votes: :member)
                       .order("meetings.starts_at DESC")

    # Record enrichment: group appearances by date for fuzzy name matching in the view helper.
    # AI-generated factual_record "meeting" labels don't exactly match Meeting body_name
    # (date suffixes, separator differences, status annotations) — see enrich_record_entry.
    @record_meetings = @topic.topic_appearances
                             .includes(meeting: :meeting_summaries, agenda_item: [])
                             .group_by { |a| a.appeared_at.to_date.to_s }

    # Coming Up fallback: most frequent committee for this topic
    @typical_committee = @topic.topic_appearances
                               .joins(:meeting)
                               .group("meetings.body_name")
                               .order(Arel.sql("COUNT(*) DESC"))
                               .limit(1)
                               .pick("meetings.body_name")
  rescue ActiveRecord::RecordNotFound
    redirect_to topics_path, alert: "Topic not found."
  end
end
