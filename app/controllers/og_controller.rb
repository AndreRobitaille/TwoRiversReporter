class OgController < ApplicationController
  allow_unauthenticated_access

  layout false

  def default
    render "og/default"
  end
end
