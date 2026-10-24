class MeetingArchivesController < ApplicationController
  allow_unauthenticated_access

  PAGE_SIZE = 50

  before_action :load_archive

  def index
  end

  def show
    @month = Date.new(params[:year].to_i, params[:month].to_i, 1)
    index = @months.index(@month)
    raise ActiveRecord::RecordNotFound unless index

    @newer_month = @months[index - 1] if index.positive?
    @older_month = @months[index + 1]
    page_segment = request.path_parameters[:page]
    @page = (page_segment || "1").to_i
    meetings = @archive.meetings_for(@month)
    @page_count = (meetings.size.to_f / PAGE_SIZE).ceil
    raise ActiveRecord::RecordNotFound unless @page.between?(1, @page_count)

    if page_segment == "1"
      return redirect_to meeting_archive_month_path(year: @month.year, month: @month.strftime("%m")), status: :moved_permanently
    end

    @meetings = meetings.slice((@page - 1) * PAGE_SIZE, PAGE_SIZE)
  end

  private

    def load_archive
      @archive = ResidentContent::MeetingArchive.new
      @months = @archive.months
    end
end
