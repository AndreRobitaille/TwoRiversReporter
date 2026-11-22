module Admin
  class CouncilFormalSourcesController < BaseController
    before_action :set_source, only: %i[show edit update]

    def index
      @sources = CouncilFormalSource.order(updated_at: :desc, id: :desc)
    end

    def new
      @source = CouncilFormalSource.new(record_kind: "unknown")
    end

    def create
      @source = CouncilFormalSource.new
      save_source(:new)
    end

    def show
      @reviews = @source.reviews.order(created_at: :desc)
      @review = params[:version].present? ? @source.reviews.find(params[:version]) : @source.current_review
      @cost = Campaigns::CostPreflight.for_stage(@review) if @review
    end

    def edit
    end

    def update
      save_source(:edit)
    end

    private

    def set_source
      @source = CouncilFormalSource.find(params[:id])
    end

    def save_source(failure_view)
      attributes = params.require(:council_formal_source).permit(:title, :case_reference, :reviewing_body, :policy_label,
        :source_url, :record_kind, :published_on, :permitted_text, :subject_names_text, :private_notes, :active, service_period_keys: [])
      attributes[:service_period_keys] = Array(attributes[:service_period_keys]).reject(&:blank?) if attributes.key?(:service_period_keys)
      @source.assign_attributes(attributes)
      @source.verified_by = params[:verified] == "1" ? Current.user : nil
      @source.verified_at = params[:verified] == "1" ? Time.current : nil
      if @source.save
        redirect_to admin_council_formal_source_path(@source), notice: "Formal record saved. Processing requires an explicit allowance."
      else
        render failure_view, status: :unprocessable_entity
      end
    end
  end
end
