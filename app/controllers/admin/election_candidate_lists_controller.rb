module Admin
  class ElectionCandidateListsController < BaseController
    before_action :set_edition
    before_action :return_to_existing_list, only: %i[new create]
    before_action :set_candidate_list, only: %i[edit update destroy]

    def new
      @candidate_list = CouncilElectionCandidateList.new
      render :form
    end

    def create
      @candidate_list = CouncilElectionCandidateList.new(election_on: @edition.election_on)
      save_candidate_list("Candidate list published.")
    rescue ActiveRecord::RecordNotUnique
      redirect_to admin_elections_path(year: @year), notice: "This election already has a candidate list.", status: :see_other
    end

    def edit
      render :form
    end

    def update
      save_candidate_list("Candidate list updated.")
    end

    def destroy
      @candidate_list.destroy!
      redirect_to admin_elections_path(year: @year), notice: "Candidate list removed.", status: :see_other
    end

    private

    def set_edition
      @edition = ResidentContent::CouncilElection.for_year(params[:year])
      raise ActiveRecord::RecordNotFound unless @edition

      @year = @edition.election_on.year
    end

    def return_to_existing_list
      return if @edition.candidates.empty?

      redirect_to admin_elections_path(year: @year), notice: "This election already has a candidate list.", status: :see_other
    end

    def set_candidate_list
      @candidate_list = CouncilElectionCandidateList.find_by!(id: params[:id], election_on: @edition.election_on)
    end

    def save_candidate_list(notice)
      input = params.expect(council_election_candidate_list: %i[names source_url])
      attributes = { names: @edition.normalize_candidate_names(input[:names]), source_url: input[:source_url] }
      if @candidate_list.with_lock { @candidate_list.update(attributes) }
        redirect_to admin_elections_path(year: @year), notice: notice, status: :see_other
      else
        render :form, status: :unprocessable_entity
      end
    end
  end
end
