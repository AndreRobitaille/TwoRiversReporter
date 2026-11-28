class CandidatePortraitsController < ApplicationController
  allow_unauthenticated_access

  def show
    photo = CandidatePortrait.find(params[:id])
    raise ActiveRecord::RecordNotFound if ResidentContent::ElectionPublication.current.withdrawn_portrait?(photo)

    if stale?(etag: photo.image_key, public: false)
      send_data photo.thumbnail, type: "image/jpeg", disposition: "inline"
    end
  end
end
