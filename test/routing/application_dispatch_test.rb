require "test_helper"

class ApplicationDispatchTest < ActiveSupport::TestCase
  test "repository controller routes dispatch to implemented public actions" do
    missing = Rails.application.routes.routes.filter_map do |route|
      controller_name = route.defaults[:controller]
      next unless controller_name && Rails.root.join("app/controllers/#{controller_name}_controller.rb").file?

      controller = "#{controller_name.camelize}Controller".constantize
      action = route.defaults[:action]
      "#{route.verb} #{route.path.spec}: #{controller_name}##{action}" unless controller.action_methods.include?(action)
    end
    assert_empty missing, "unsupported application dispatches:\n#{missing.join("\n")}"
  end

  test "alias promotion has one declaration and compatibility actions stay routable" do
    routes = Rails.application.routes.routes
    promotions = routes.select { |route| route.defaults.slice(:controller, :action) == { controller: "admin/topic_repairs", action: "promote_alias" } }
    assert_equal 1, promotions.size
    %w[bulk_update merge create_alias].each do |action|
      assert routes.any? { |route| route.defaults[:controller] == "admin/topics" && route.defaults[:action] == action }, "Phase 2 compatibility action #{action} must remain"
    end
  end
end
