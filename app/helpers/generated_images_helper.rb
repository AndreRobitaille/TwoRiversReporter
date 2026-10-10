module GeneratedImagesHelper
  CARD_IMAGE_VARIANTS = {
    standard: { width: 396, height: 264 },
    compact: { width: 204, height: 152 },
    feature: { width: 800, height: 533 }
  }.freeze

  def generated_image_variant(generated_image, size: :standard)
    dimensions = CARD_IMAGE_VARIANTS.fetch(size)

    resize = if generated_image_uploaded?(generated_image)
      { resize_and_pad: [ dimensions[:width], dimensions[:height], { background: [ 255, 255, 255 ] } ] }
    else
      { resize_to_fill: [ dimensions[:width], dimensions[:height] ] }
    end

    generated_image.file.variant(**resize,
      format: :webp,
      saver: { quality: 82 }
    )
  end

  def generated_image_proxy_path(generated_image, size: :standard)
    # Keep the browser on one stable URL instead of a cached redirect to a
    # short-lived disk URL, which WebKit can revalidate without a usable body.
    rails_storage_proxy_path(generated_image_variant(generated_image, size: size))
  end

  def generated_image_dimensions(size: :standard)
    CARD_IMAGE_VARIANTS.fetch(size)
  end

  def generated_image_uploaded?(generated_image)
    generated_image.source_generation_tier == "admin_upload"
  end

  def generated_image_cutline(generated_image)
    generated_image_uploaded?(generated_image) ? "Uploaded image" : "AI image"
  end
end
