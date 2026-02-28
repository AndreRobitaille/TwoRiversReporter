module Admin
  class CommitteesController < BaseController
    before_action :set_committee, only: %i[show edit update destroy create_alias destroy_alias]

    def index
      @committees = Committee.all.order(:name)
      @committees = @committees.where(committee_type: params[:type]) if params[:type].present?
      @committees = @committees.where(status: params[:status]) if params[:status].present?
    end

    def show
      @aliases = @committee.committee_aliases.order(:name)
      @memberships = @committee.committee_memberships.includes(:member).order(ended_on: :desc, started_on: :desc)
    end

    def new
      @committee = Committee.new
    end

    def create
      @committee = Committee.new(committee_params)

      if @committee.save
        redirect_to admin_committee_path(@committee), notice: "Committee created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @committee.update(committee_params)
        redirect_to admin_committee_path(@committee), notice: "Committee updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @committee.destroy
      redirect_to admin_committees_path, notice: "Committee deleted."
    end

    def create_alias
      @alias = @committee.committee_aliases.build(name: params[:name])

      if @alias.save
        redirect_to admin_committee_path(@committee), notice: "Alias added."
      else
        redirect_to admin_committee_path(@committee), alert: "Failed: #{@alias.errors.full_messages.join(', ')}"
      end
    end

    def destroy_alias
      alias_record = @committee.committee_aliases.find(params[:alias_id])
      alias_record.destroy
      redirect_to admin_committee_path(@committee), notice: "Alias removed."
    end

    private

    def set_committee
      @committee = Committee.find(params[:id])
    end

    def committee_params
      params.require(:committee).permit(:name, :description, :committee_type, :status, :established_on, :dissolved_on)
    end
  end
end
