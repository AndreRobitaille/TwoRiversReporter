class PagesController < ApplicationController
  allow_unauthenticated_access only: :about

  def about
  end
end
