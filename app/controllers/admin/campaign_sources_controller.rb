module Admin
  class CampaignSourcesController < BaseController
    before_action :set_source, only: %i[show edit update]

    def index
      @sources = CampaignSource.order(updated_at: :desc, id: :desc)
    end

    def new
      @source = CampaignSource.new
    end

    def create
      @source = CampaignSource.new(source_params)
      if existing = CampaignSource.find_by(source_url: @source.source_url)
        redirect_to admin_campaign_source_path(existing), notice: "This article is already saved. Use Edit article to change it."
        return
      end
      save_source(:new)
    end

    def show
      @versions = @source.versions.order(created_at: :desc, id: :desc)
      @version = params[:version].present? ? @versions.find(params[:version]) : @source.current_version
      @extraction = @version.extraction
    end

    def edit
    end

    def update
      @source.assign_attributes(source_params)
      save_source(:edit)
    end

    private

    def set_source
      @source = CampaignSource.find(params[:id])
    end

    def source_params
      params.require(:campaign_source).permit(*CampaignSource::SNAPSHOT_FIELDS)
    end

    def save_source(failure_view)
      @source.submitted_by = Current.user
      if @source.save
        redirect_to admin_campaign_source_path(@source), notice: "Article saved. Analysis has not been enabled."
      else
        render failure_view, status: :unprocessable_entity
      end
    end
  end
end
