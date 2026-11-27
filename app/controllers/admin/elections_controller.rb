module Admin
  class ElectionsController < BaseController
    def index
      @workspace = ElectionWorkspace.new(params[:year])
    end

    def find_htr
      workspace = ElectionWorkspace.new(params[:year])
      return head :not_found unless workspace.year == params[:year] && (workspace.filing_edition || workspace.edition.present?)

      DiscoverHtrQuestionnairesJob.perform_later(workspace.date.year)
      redirect_to admin_elections_path(year: workspace.year), status: :see_other,
        notice: "HTR search queued. Refresh this election to see any articles found."
    end
  end
end
