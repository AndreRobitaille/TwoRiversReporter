class MeetingsController < ApplicationController
  UPCOMING_WINDOW = 21.days
  RECENT_WINDOW = 21.days

  def index
    upcoming_all = Meeting
      .where(starts_at: Time.current..UPCOMING_WINDOW.from_now)
      .includes(:committee, :meeting_documents, :meeting_summaries, agenda_items: :topics)
      .order(starts_at: :asc)

    # Split upcoming: enriched (has agenda/topics) vs thin (just scheduled)
    @upcoming_enriched, @upcoming_thin = deduplicate_meetings(upcoming_all, :upcoming).partition { |m| meeting_has_content?(m, :upcoming) }

    recent_all = Meeting
      .where(starts_at: (RECENT_WINDOW.ago)..Time.current)
      .includes(:committee, :meeting_documents, :meeting_summaries, agenda_items: :topics)
      .order(starts_at: :desc)

    # Split recent: enriched (has summary) vs thin (no summary)
    @recent_enriched, @recent_thin = deduplicate_meetings(recent_all, :recent).partition { |m| meeting_has_content?(m, :recent) }

    if params[:q].present?
      @pagy, @search_results = pagy(:offset, Meeting.search_multi(params[:q]), limit: 15)
    end
  end

  def show
    @meeting = Meeting.find(params[:id])

    substantive_item_ids = @meeting.agenda_items.substantive.select(:id)
    approved_topics = Topic.approved
      .joins(:agenda_item_topics)
      .where(agenda_item_topics: { agenda_item_id: substantive_item_ids })
      .includes(:topic_briefing, topic_appearances: :agenda_item)
      .distinct

    @ongoing_topics, @new_topics = approved_topics.partition do |topic|
      topic.topic_appearances.count { |appearance| appearance.agenda_item.nil? || appearance.agenda_item.substantive? } > 1
    end

    @has_substantive_agenda_content = @meeting.agenda_items.any?(&:substantive?) || @meeting.meeting_summaries.any?
    @has_substantive_topic_content = approved_topics.any?

    # Supersede chain: minutes > transcript > packet > agenda preview.
    @summary = @meeting.meeting_summaries.find_by(summary_type: "minutes_recap") ||
               @meeting.meeting_summaries.find_by(summary_type: "transcript_recap") ||
               @meeting.meeting_summaries.find_by(summary_type: "packet_analysis") ||
               @meeting.meeting_summaries.find_by(summary_type: "agenda_preview")
  end

  private

  def deduplicate_meetings(meetings, zone)
    meetings.group_by(&:duplicate_identity_key)
      .values
      .map { |duplicates| preferred_duplicate(duplicates, zone) }
  end

  def preferred_duplicate(duplicates, zone)
    duplicates.max_by do |meeting|
      [
        cancelled_meeting?(meeting) ? 0 : 1,
        meeting_has_content?(meeting, zone) ? 1 : 0,
        meeting.updated_at.to_i,
        -meeting.id
      ]
    end
  end

  def cancelled_meeting?(meeting)
    meeting.body_name.to_s.match?(/\b(cancelled|canceled)\b/i)
  end

  def meeting_has_content?(meeting, zone)
    case zone
    when :upcoming
      topics = meeting.agenda_items.select(&:substantive?).flat_map(&:topics).uniq.select(&:approved?)
      topics.any? || meeting.meeting_summaries.any? || meeting.document_status.in?([ :agenda, :packet, :minutes ])
    when :recent
      meeting.meeting_summaries.any?
    end
  end
end
