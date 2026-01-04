class MeetingsController < ApplicationController
  def index
    @meetings = Meeting.order(starts_at: :desc)
  end

  def show
    @meeting = Meeting.find(params[:id])
  end
end
