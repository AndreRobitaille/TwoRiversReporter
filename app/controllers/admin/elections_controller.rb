module Admin
  class ElectionsController < BaseController
    def index
      @workspace = ElectionWorkspace.new(params[:year])
    end
  end
end
