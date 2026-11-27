class CandidatePortraitsController < ApplicationController
  allow_unauthenticated_access

  def show
    photo = CandidatePortrait.find(params[:id])
    if stale?(etag: photo.image_key, public: true)
      send_data photo.thumbnail, type: "image/jpeg", disposition: "inline"
    end
  end
end
