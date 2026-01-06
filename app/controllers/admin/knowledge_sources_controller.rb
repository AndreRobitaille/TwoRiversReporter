module Admin
  class KnowledgeSourcesController < BaseController
    before_action :set_source, only: %i[ show edit update destroy reingest ]

    def index
      @sources = KnowledgeSource.all.order(created_at: :desc)
    end

    def show
    end

    def new
      @source = KnowledgeSource.new(source_type: "note")
    end

    def create
      @source = KnowledgeSource.new(source_params)
      @source.active = true # Default to active

      if @source.save
        redirect_to admin_knowledge_source_path(@source), notice: "Knowledge source created. Ingestion queued."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @source.update(source_params)
        redirect_to admin_knowledge_source_path(@source), notice: "Knowledge source updated. Re-ingestion queued if content changed."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @source.destroy
      redirect_to admin_knowledge_sources_path, notice: "Knowledge source deleted."
    end

    def reingest
      IngestKnowledgeSourceJob.perform_later(@source.id)
      redirect_to admin_knowledge_source_path(@source), notice: "Re-ingestion queued."
    end

    private

    def set_source
      @source = KnowledgeSource.find(params[:id])
    end

    def source_params
      params.require(:knowledge_source).permit(:title, :source_type, :body, :file, :status, :verification_notes, :verified_on, :active)
    end
  end
end
