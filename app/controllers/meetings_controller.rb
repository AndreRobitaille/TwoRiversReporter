class MeetingsController < ApplicationController
  def index
    @meetings = if params[:q].present?
                  # Find meetings that have documents matching the query
                  matching_doc_ids = MeetingDocument.search(params[:q]).pluck(:meeting_id)
                  Meeting.where(id: matching_doc_ids).order(starts_at: :desc)
    else
                  Meeting.order(starts_at: :desc)
    end
  end

  def show
    @meeting = Meeting.find(params[:id])
  end
end
