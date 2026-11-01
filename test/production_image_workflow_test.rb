require "minitest/autorun"
require "yaml"

class ProductionImageWorkflowTest < Minitest::Test
  WORKFLOW = File.expand_path("../.github/workflows/runtime-image.yml", __dir__)

  def test_ci_can_build_and_export_but_cannot_publish_or_deploy
    source = File.read(WORKFLOW)
    workflow = YAML.safe_load(source)
    assert_equal({ "contents" => "read" }, workflow.fetch("permissions"))
    assert_equal "ubuntu-latest", workflow.dig("jobs", "build_and_smoke", "runs-on")
    refute_includes source, "secrets."
    steps = workflow.dig("jobs", "build_and_smoke", "steps")
    commands = steps.filter_map { |step| step["run"] }.join("\n")
    refute_match(/\b(kamal|publish-image|ssh|crane|docker\s+push)\b/, commands)
    exports = steps.select { |step| step["name"].match?(/Export verified|Retain release/) }
    assert_equal 2, exports.size
    exports.each { |step| assert_equal "github.event_name != 'pull_request'", step["if"] }
    triggers = workflow["on"] || workflow.fetch(true)
    assert_equal [ "master" ], triggers.dig("push", "branches")
    assert triggers.key?("workflow_dispatch")
    assert_includes triggers.dig("pull_request", "paths"), "db/**"
  end
end
