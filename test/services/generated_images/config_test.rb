require "test_helper"

class GeneratedImages::ConfigTest < ActiveSupport::TestCase
  test "enabled is true only when env var is exact true string" do
    original = ENV["GENERATED_IMAGES_ENABLED"]

    ENV["GENERATED_IMAGES_ENABLED"] = "true"
    assert GeneratedImages::Config.enabled?

    [ nil, "false", "TRUE", "1", "yes", " true " ].each do |value|
      ENV["GENERATED_IMAGES_ENABLED"] = value
      assert_not GeneratedImages::Config.enabled?, "expected #{value.inspect} to be disabled"
    end
  ensure
    ENV["GENERATED_IMAGES_ENABLED"] = original
  end
end
