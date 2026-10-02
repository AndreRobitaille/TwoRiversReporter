module Api
  class HandbooksController < BaseController
    def show
      render_data(Handbook.new(base_url: request.base_url).to_h)
    end
  end
end
