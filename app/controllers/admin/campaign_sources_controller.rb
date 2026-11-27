module Admin
  class CampaignSourcesController < BaseController
    before_action :set_source, only: %i[show edit update analyze]
    before_action :use_forum_import, only: %i[edit update]

    def index
      @sources = CampaignSource.order(updated_at: :desc, id: :desc)
    end

    def new
      @source = new_article
      if @questionnaire && (saved = CampaignSource.find_by(source_url: @source.source_url))
        redirect_to admin_campaign_source_path(saved)
      end
    end

    def create
      @source = new_article
      @source.assign_attributes(@questionnaire ? source_params.slice(:body) : source_params)
      if existing = CampaignSource.find_by(source_url: @source.source_url)
        redirect_to admin_campaign_source_path(existing), notice: "This article is already saved. Open the saved answers to make a correction."
        return
      end
      save_source(:new)
    end

    def show
      @versions = @source.versions.order(created_at: :desc, id: :desc)
      @version = params[:version].present? ? @versions.find(params[:version]) : @source.current_version
      identify_questionnaire(@version)
      if @questionnaire && params[:view] != "processing"
        @progress = QuestionnaireProgress.new(@version)
        return
      end

      @extraction = @version.extraction
      @topic_matching = @version.topic_matching
      if params[:view] == "processing" && !@questionnaire
        @cost_preflight = Campaigns::CostPreflight.call(@version)
        @matching_cost = Campaigns::CostPreflight.for_stage(@topic_matching) if @topic_matching
      end
    end

    def analyze
      version = @source.current_version
      if version.id.to_s != params[:version_id].to_s
        redirect_to admin_campaign_source_path(@source), alert: "The source changed. Check the current version before starting analysis.", status: :see_other
      elsif Campaigns::AnalysisRun.for(version.extraction)
        ExtractCampaignSourceJob.perform_later(@source.id, version_id: version.id)
        redirect_to admin_campaign_source_path(@source), notice: "Analysis queued for this source.", status: :see_other
      else
        redirect_to admin_campaign_source_path(@source), alert: "Analysis can’t start yet. Check the current source status.", status: :see_other
      end
    end

    def edit
      identify_questionnaire(@source) unless params[:details]
    end

    def update
      identify_questionnaire(@source) if params[:answers]
      @source.assign_attributes(@questionnaire ? source_params.slice(:body) : source_params)
      save_source(:edit)
    end

    private

    def new_article
      edition = Campaigns::ElectionBackfill.for(params[:year])
      @year = params[:year] if edition
      election_on = edition&.fetch("election_on")
      if election_on.nil? && params[:year].present?
        workspace = ElectionWorkspace.new(params[:year])
        election_on = workspace.date if workspace.year == params[:year]
      end
      @questionnaire = Campaigns::ElectionBackfill.lead(@year, params[:lead], kind: "article")
      lead = @questionnaire || {}
      CampaignSource.new(lead.slice("title", "publisher", "published_on").merge(
        source_url: lead["url"], election_on: election_on,
        coverage: lead["section"] ? "selected_excerpts" : "full_article", coverage_notes: lead["section"]))
    end

    def identify_questionnaire(record)
      @year = record.election_on.year
      @return_year = params[:from_year].to_s.match?(/\A[0-9]{4}\z/) ? params[:from_year] : @year
      return if record.forum?

      @questionnaire = Campaigns::ElectionBackfill.catalog_article(record)
      @questionnaire ||= { "publisher" => record.publisher, "link_label" => "Open HTR article" } if Campaigns::ElectionBackfill.htr?(record)
    end

    def set_source
      @source = CampaignSource.find(params[:id])
    end

    def source_params
      params.require(:campaign_source).permit(*(CampaignSource::SNAPSHOT_FIELDS - [ "prepared_transcript" ]))
    end

    def use_forum_import
      redirect_to new_admin_campaign_forum_path(source_id: @source.id) if @source.forum?
    end

    def save_source(failure_view)
      notice = @questionnaire ? "Council answers saved for #{@year}." : "Article saved."
      excerpt = Campaigns::ElectionBackfill.before_end_heading(@source.body, @questionnaire)
      if excerpt
        if excerpt.blank?
          @source.errors.add(:body, "must include Council answers above the school board heading.")
          return render failure_view, status: :unprocessable_entity
        end
        @source.body = excerpt
        notice += " The school board section was left out."
      end
      @source.submitted_by = Current.user
      if @source.save
        redirect_to admin_campaign_source_path(@source, from_year: params[:from_year]), notice: notice
      else
        render failure_view, status: :unprocessable_entity
      end
    end
  end
end
