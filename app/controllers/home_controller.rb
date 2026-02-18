class HomeController < ApplicationController
  UPCOMING_WINDOW = 30.days
  RECENT_WINDOW = 14.days
  CARD_LIMIT = 5
  COMING_UP_MIN_IMPACT = 3
  WHAT_HAPPENED_MIN_IMPACT = 2
  WHAT_HAPPENED_WINDOW = 30.days

  def index
    @coming_up = build_coming_up
    @what_happened = build_what_happened
    @upcoming_meeting_groups = upcoming_meetings_grouped
    @recent_meeting_groups = recent_meetings_grouped
  end

  private

  def build_coming_up
    upcoming_topic_ids = TopicAppearance
      .joins(:meeting)
      .where(meetings: { starts_at: Time.current.. })
      .select(:topic_id).distinct

    topics = Topic.approved
      .where(id: upcoming_topic_ids)
      .where("resident_impact_score >= ?", COMING_UP_MIN_IMPACT)
      .order(resident_impact_score: :desc)
      .limit(CARD_LIMIT)

    attach_headlines(topics)
  end

  def build_what_happened
    # Topics with recent motions
    motion_topic_ids = AgendaItemTopic
      .joins(agenda_item: :motions)
      .where(motions: { created_at: WHAT_HAPPENED_WINDOW.ago.. })
      .select(:topic_id).distinct

    # Topics with recent status events
    event_topic_ids = TopicStatusEvent
      .where(occurred_at: WHAT_HAPPENED_WINDOW.ago..)
      .select(:topic_id).distinct

    topics = Topic.approved
      .where(id: motion_topic_ids)
      .or(Topic.approved.where(id: event_topic_ids))
      .where("resident_impact_score >= ?", WHAT_HAPPENED_MIN_IMPACT)
      .order(resident_impact_score: :desc, last_activity_at: :desc)
      .limit(CARD_LIMIT)

    attach_headlines(topics)
  end

  def attach_headlines(topics)
    return [] if topics.empty?

    topic_ids = topics.map(&:id)
    latest_summaries = TopicSummary
      .where(topic_id: topic_ids, summary_type: "topic_digest")
      .order(:topic_id, created_at: :desc)
      .select("DISTINCT ON (topic_id) topic_id, generation_data")

    @headlines ||= {}
    latest_summaries.each do |summary|
      headline = summary.generation_data&.dig("headline")
      @headlines[summary.topic_id] = headline if headline.present?
    end

    topics
  end

  def upcoming_meetings_grouped
    meetings = Meeting.in_window(Time.current, UPCOMING_WINDOW.from_now)
                      .includes(:meeting_documents, :meeting_summaries, :motions,
                                agenda_items: { agenda_item_topics: :topic })
                      .order(starts_at: :asc)

    group_meetings_by_week(meetings, :future)
  end

  def recent_meetings_grouped
    meetings = Meeting.in_window(RECENT_WINDOW.ago, Time.current)
                      .includes(:meeting_documents, :meeting_summaries, :motions,
                                agenda_items: { agenda_item_topics: :topic })
                      .order(starts_at: :desc)

    group_meetings_by_week(meetings, :past)
  end

  def group_meetings_by_week(meetings, direction)
    meetings.group_by { |m| week_key(m.starts_at) }
            .map do |week_start, week_meetings|
              {
                label: week_label(week_start, direction),
                meetings: week_meetings
              }
            end
  end

  def week_key(time)
    time.beginning_of_week(:monday).to_date
  end

  def week_label(week_start, direction)
    today = Date.current
    this_week_start = today.beginning_of_week(:monday)

    case week_start
    when this_week_start
      "This Week"
    when this_week_start + 1.week
      "Next Week"
    when this_week_start - 1.week
      "Last Week"
    else
      week_end = week_start + 6.days
      if direction == :future
        "#{week_start.strftime('%b %-d')} \u2013 #{week_end.strftime('%b %-d')}"
      else
        "#{week_start.strftime('%b %-d')} \u2013 #{week_end.strftime('%b %-d')}"
      end
    end
  end
end
