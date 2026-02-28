class MeetingsController < ApplicationController
  def index
    @meetings = if params[:q].present?
                  # Find meetings that have documents matching the query
                  matching_doc_ids = MeetingDocument.search(params[:q]).pluck(:meeting_id)
                  Meeting.where(id: matching_doc_ids).includes(:meeting_documents, :meeting_summaries, :motions).order(starts_at: :desc)
    else
                  Meeting.includes(:meeting_documents, :meeting_summaries, :motions).order(starts_at: :desc)
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
  end
end
