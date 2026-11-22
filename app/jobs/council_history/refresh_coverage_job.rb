module CouncilHistory
  class RefreshCoverageJob < ApplicationJob
    def perform
      Coverage.refresh!
    end
  end
end
