require "test_helper"

class DeployConfigTest < ActiveSupport::TestCase
  test "generated images env is enabled in clear env" do
    deploy = YAML.load_file(Rails.root.join("config/deploy.yml"))

    assert_equal "true", deploy.dig("env", "clear", "GENERATED_IMAGES_ENABLED")
  end
end
