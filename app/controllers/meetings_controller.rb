class MeetingsController < ApplicationController
  UPCOMING_WINDOW = 21.days
  RECENT_WINDOW = 21.days

  def index
    upcoming_all = Meeting
      .where(starts_at: Time.current..UPCOMING_WINDOW.from_now)
      .includes(:committee, :meeting_documents, :meeting_summaries, agenda_items: :topics)
      .order(starts_at: :asc)

    # Split upcoming: enriched (has agenda/topics) vs thin (just scheduled)
    @upcoming_enriched, upcoming_thin = upcoming_all.partition { |m| meeting_has_content?(m, :upcoming) }
    @upcoming_thin_count = upcoming_thin.size

    recent_all = Meeting
      .where(starts_at: (RECENT_WINDOW.ago)..Time.current)
      .includes(:committee, :meeting_documents, :meeting_summaries, agenda_items: :topics)
      .order(starts_at: :desc)

    # Split recent: enriched (has summary) vs thin (no summary)
    @recent_enriched, recent_thin = recent_all.partition { |m| meeting_has_content?(m, :recent) }
    @recent_thin_count = recent_thin.size

    if params[:q].present?
      @pagy, @search_results = pagy(:offset, Meeting.search_multi(params[:q]), limit: 15)
    end
  end

  def show
    @meeting = Meeting.find(params[:id])

    approved_topics = @meeting.topics.approved
      .includes(:topic_appearances, :topic_briefing)
      .distinct

    @ongoing_topics, @new_topics = approved_topics.partition do |topic|
      topic.topic_appearances.size > 1
    end

    # Prefer minutes_recap over transcript_recap over packet_analysis
    @summary = @meeting.meeting_summaries.find_by(summary_type: "minutes_recap") ||
               @meeting.meeting_summaries.find_by(summary_type: "transcript_recap") ||
               @meeting.meeting_summaries.find_by(summary_type: "packet_analysis")
  end

  private

  def meeting_has_content?(meeting, zone)
    case zone
    when :upcoming
      topics = meeting.agenda_items.flat_map(&:topics).uniq.select(&:approved?)
      topics.any? || meeting.document_status.in?([ :agenda, :packet, :minutes ])
    when :recent
      meeting.meeting_summaries.any?
    end
  end
end
