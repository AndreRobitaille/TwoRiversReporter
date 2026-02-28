class HomeController < ApplicationController
  UPCOMING_WINDOW = 30.days
  RECENT_WINDOW = 14.days
  CARD_LIMIT = 5
  COMING_UP_MIN_IMPACT = 3
  WHAT_HAPPENED_MIN_IMPACT = 2
  WHAT_HAPPENED_WINDOW = 30.days
  COMING_UP_OVER_FETCH = 15
  MAX_TOPICS_PER_MEETING = 2

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

    candidates = Topic.approved
      .where(id: upcoming_topic_ids)
      .where("resident_impact_score >= ?", COMING_UP_MIN_IMPACT)
      .order(resident_impact_score: :desc)
      .limit(COMING_UP_OVER_FETCH)

    topics = apply_meeting_diversity(candidates)
    attach_coming_up_headlines(topics)
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

    attach_what_happened_headlines(topics)
  end

  def attach_coming_up_headlines(topics)
    return [] if topics.empty?

    briefings = TopicBriefing.where(topic_id: topics.map(&:id))
    @coming_up_headlines = {}
    briefings.each do |b|
      @coming_up_headlines[b.topic_id] = b.upcoming_headline if b.upcoming_headline.present?
    end

    topics
  end

  def attach_what_happened_headlines(topics)
    return [] if topics.empty?

    briefings = TopicBriefing.where(topic_id: topics.map(&:id))
    @what_happened_headlines = {}
    briefings.each do |b|
      @what_happened_headlines[b.topic_id] = b.headline if b.headline.present?
    end

    topics
  end

  def apply_meeting_diversity(candidates)
    return candidates.to_a if candidates.empty?

    topic_ids = candidates.map(&:id)
    next_meetings = TopicAppearance
      .joins(:meeting)
      .where(topic_id: topic_ids, meetings: { starts_at: Time.current.. })
      .order(Arel.sql("topic_id, meetings.starts_at ASC"))
      .select("DISTINCT ON (topic_id) topic_id, meeting_id")

    topic_to_meeting = next_meetings.each_with_object({}) { |row, h| h[row.topic_id] = row.meeting_id }
    meeting_counts = Hash.new(0)
    result = []

    candidates.each do |topic|
      meeting_id = topic_to_meeting[topic.id]
      next unless meeting_id
      next if meeting_counts[meeting_id] >= MAX_TOPICS_PER_MEETING

      result << topic
      meeting_counts[meeting_id] += 1
      break if result.size >= CARD_LIMIT
    end

    result
  end

  def upcoming_meetings_grouped
    meetings = Meeting.in_window(Time.current - MeetingsHelper::MEETING_BUFFER, UPCOMING_WINDOW.from_now)
                      .includes(:meeting_documents, :meeting_summaries, :motions,
                                agenda_items: { agenda_item_topics: :topic })
                      .order(starts_at: :asc)

    group_meetings_by_week(meetings, :future)
  end

  def recent_meetings_grouped
    meetings = Meeting.in_window(RECENT_WINDOW.ago, Time.current - MeetingsHelper::MEETING_BUFFER)
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
