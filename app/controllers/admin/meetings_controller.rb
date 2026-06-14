module Admin
  class MeetingsController < BaseController
    def show
      @meeting = Meeting.includes(:committee).find(params[:id])
      @meeting_display_name = helpers.clean_meeting_display(@meeting.body_name).presence || "Meeting"
    end
  end
end
