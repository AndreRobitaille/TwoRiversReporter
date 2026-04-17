class OgController < ApplicationController
  layout false

  def default
    render "og/default"
  end
end
