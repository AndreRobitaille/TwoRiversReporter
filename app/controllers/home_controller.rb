class HomeController < ApplicationController
  include HighlightSignals

  UPCOMING_WINDOW = 30.days
  RECENT_WINDOW = 14.days
  CARD_LIMIT = 5

  def index
    @worth_watching = build_worth_watching
    @recent_signals = build_recent_signals
    @upcoming_meeting_groups = upcoming_meetings_grouped
    @recent_meeting_groups = recent_meetings_grouped
  end

  private

  def build_worth_watching
    # Topics appearing on future meeting agendas
    upcoming_topic_ids = TopicAppearance
      .joins(:meeting)
      .where(meetings: { starts_at: Time.current.. })
      .select(:topic_id).distinct

    # Topics with recent highlight signals
    signal_topic_ids = TopicStatusEvent
      .where(evidence_type: HIGHLIGHT_EVENT_TYPES)
      .where(occurred_at: HIGHLIGHT_WINDOW.ago..)
      .select(:topic_id).distinct

    topics = Topic.publicly_visible
                  .where(id: upcoming_topic_ids)
                  .or(Topic.publicly_visible.where(id: signal_topic_ids))
                  .where(lifecycle_status: %w[active recurring])
                  .limit(CARD_LIMIT)

    # Attach next appearance info and signals
    topic_ids = topics.map(&:id)
    @worth_watching_signals = build_highlight_signals(topic_ids)
    @worth_watching_next_appearances = next_appearances_for(topic_ids)

    topics
  end

  def build_recent_signals
    events = TopicStatusEvent
      .where(evidence_type: HIGHLIGHT_EVENT_TYPES)
      .where(occurred_at: HIGHLIGHT_WINDOW.ago..)
      .where(topic_id: Topic.publicly_visible.select(:id))
      .order(occurred_at: :desc)
      .select(:topic_id, :evidence_type, :lifecycle_status, :occurred_at)

    # Group by topic, keep most recent event time
    topic_event_map = {}
    signals = {}
    events.each do |event|
      topic_event_map[event.topic_id] ||= event.occurred_at

      label = helpers.highlight_signal_label(event.evidence_type, event.lifecycle_status)
      next unless label

      signals[event.topic_id] ||= []
      signals[event.topic_id] << label unless signals[event.topic_id].include?(label)
    end

    @recent_signals_map = signals
    @recent_signals_times = topic_event_map

    # Return topics ordered by most recent event
    topic_ids = topic_event_map.keys.first(CARD_LIMIT)
    return Topic.none if topic_ids.empty?

    Topic.publicly_visible
         .where(id: topic_ids)
         .index_by(&:id)
         .values_at(*topic_ids)
         .compact
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

  def next_appearances_for(topic_ids)
    return {} if topic_ids.empty?

    TopicAppearance
      .joins(:meeting)
      .where(topic_id: topic_ids)
      .where(meetings: { starts_at: Time.current.. })
      .order(Arel.sql("topic_appearances.topic_id, meetings.starts_at ASC"))
      .select("DISTINCT ON (topic_appearances.topic_id) topic_appearances.topic_id, meetings.starts_at, meetings.body_name")
      .each_with_object({}) do |row, hash|
        hash[row.topic_id] = { starts_at: row.starts_at, body_name: row.body_name }
      end
  end
end
