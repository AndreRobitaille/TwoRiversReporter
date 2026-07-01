module Admin
  class MeetingsController < BaseController
    def index
      @meetings = Meeting
        .includes(:committee)
        .order(Arel.sql("CASE WHEN starts_at IS NULL THEN 1 ELSE 0 END"), starts_at: :desc, id: :desc)
        .limit(100)
      @latest_generated_images_by_meeting_id = latest_generated_images_by_meeting_id(@meetings)
    end

    def show
      @meeting = Meeting.includes(:committee).find(params[:id])
      @meeting_display_name = helpers.clean_meeting_display(@meeting.body_name).presence || "Meeting"
    end

    private

      def latest_generated_images_by_meeting_id(meetings)
        meeting_ids = meetings.map(&:id)
        return {} if meeting_ids.empty?

        GeneratedImage
          .where(imageable_type: "Meeting", imageable_id: meeting_ids)
          .order(created_at: :desc, updated_at: :desc, id: :desc)
          .each_with_object({}) do |image, latest_images|
            latest_images[image.imageable_id] ||= image
          end
      end
  end
end
