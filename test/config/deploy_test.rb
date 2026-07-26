require "test_helper"

class DeployConfigTest < ActiveSupport::TestCase
  test "generated images env is enabled in clear env" do
    deploy = YAML.load_file(Rails.root.join("config/deploy.yml"))

    assert_equal "true", deploy.dig("env", "clear", "GENERATED_IMAGES_ENABLED")
  end

  test "the production proxy caps request bodies before Rack parses them" do
    deploy = YAML.load_file(Rails.root.join("config/deploy.yml"))

    assert_equal 25.megabytes, deploy.dig("env", "clear", "MAX_REQUEST_BODY")
  end
end
