class MeetingsController < ApplicationController
  UPCOMING_WINDOW = 21.days
  RECENT_WINDOW = 21.days

  def index
    @upcoming = Meeting
      .where(starts_at: Time.current..UPCOMING_WINDOW.from_now)
      .includes(:committee, :meeting_documents, :meeting_summaries, agenda_items: :topics)
      .order(starts_at: :asc)

    @recent = Meeting
      .where(starts_at: (RECENT_WINDOW.ago)..Time.current)
      .includes(:committee, :meeting_documents, :meeting_summaries, agenda_items: :topics)
      .order(starts_at: :desc)

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
end
