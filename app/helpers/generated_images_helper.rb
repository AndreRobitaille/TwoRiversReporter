module GeneratedImagesHelper
  CARD_IMAGE_VARIANTS = {
    standard: { width: 396, height: 264 },
    compact: { width: 204, height: 152 },
    feature: { width: 800, height: 533 }
  }.freeze

  def generated_image_variant(generated_image, size: :standard)
    dimensions = CARD_IMAGE_VARIANTS.fetch(size)

    generated_image.file.variant(
      resize_to_fill: [ dimensions[:width], dimensions[:height] ],
      format: :webp,
      saver: { quality: 82 }
    )
  end

  def generated_image_dimensions(size: :standard)
    CARD_IMAGE_VARIANTS.fetch(size)
  end
end
