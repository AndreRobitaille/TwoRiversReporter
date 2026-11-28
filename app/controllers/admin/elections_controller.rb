module Admin
  class ElectionsController < BaseController
    def index
      @workspace = ElectionWorkspace.new(params[:year])
    end

    def find_forums
      queue_discovery(DiscoverElectionForumsJob, "Forum search queued. Refresh this election to see any forums found.")
    end

    def find_htr
      queue_discovery(DiscoverHtrQuestionnairesJob, "HTR search queued. Refresh this election to see any articles found.")
    end

    private

    def queue_discovery(job, notice)
      workspace = ElectionWorkspace.new(params[:year])
      return head :not_found unless workspace.year == params[:year] && (workspace.filing_edition || workspace.edition.present?)

      job.perform_later(workspace.date.year)
      redirect_to admin_elections_path(year: workspace.year), status: :see_other, notice: notice
    end
  end
end
