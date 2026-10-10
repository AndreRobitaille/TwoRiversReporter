require "test_helper"
require "vips"

class GeneratedImagesHelperTest < ActionView::TestCase
  test "uploaded map variants preserve top and bottom edge content" do
    topic = Topic.create!(name: "map image preservation", status: "approved")
    image = topic.generated_images.create!(status: "ready", purpose: "feature_and_og", source_generation_tier: "admin_upload")
    canvas = Vips::Image.black(400, 300).new_from_image([ 255, 255, 255 ])
    top_edge = Vips::Image.black(400, 30).new_from_image([ 255, 0, 0 ])
    bottom_edge = Vips::Image.black(400, 30).new_from_image([ 0, 0, 255 ])
    bytes = canvas.insert(top_edge, 0, 0).insert(bottom_edge, 0, 270).write_to_buffer(".png")
    image.file.attach(io: StringIO.new(bytes), filename: "map-boundaries.png", content_type: "image/png")

    variant = generated_image_variant(image, size: :feature).processed
    rendered = Vips::Image.new_from_buffer(variant.download, "")
    assert_equal [ 800, 533 ], [ rendered.width, rendered.height ]
    top = rendered.getpoint(400, 10)
    bottom = rendered.getpoint(400, 523)
    assert top[0] > 200 && top[1] < 30 && top[2] < 30, "top edge must survive"
    assert bottom[2] > 200 && bottom[0] < 30 && bottom[1] < 30, "bottom edge must survive"
    assert_equal "Uploaded image", generated_image_cutline(image)
  end
end
