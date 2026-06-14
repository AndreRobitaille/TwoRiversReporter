module LoadsGeneratedImages
  extend ActiveSupport::Concern

  private

  # Batch-loads ready generated images for a set of imageable records (Topics or
  # Meetings), returning { imageable_id => GeneratedImage } with the newest
  # usable image per record. Avoids N+1 by preloading attachments/blobs.
  #
  # surface: :og (topic cards/social) or :feature (meeting cards/feature).
  def generated_images_for(records, surface:)
    records = Array(records).compact
    return {} if records.empty?

    imageable_type = records.first.class.base_class.name
    imageable_ids = records.map(&:id)
    purposes = surface.to_s == "og" ? %w[og feature_and_og] : %w[feature feature_and_og]

    GeneratedImage.ready
      .where(imageable_type: imageable_type, imageable_id: imageable_ids)
      .where(purpose: purposes)
      .includes(file_attachment: :blob)
      .newest
      .each_with_object({}) do |image, images_by_id|
        next unless image.file.attached?

        images_by_id[image.imageable_id] ||= image
      end
  end
end
