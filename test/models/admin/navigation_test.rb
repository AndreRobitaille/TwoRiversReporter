require "test_helper"

module Admin
  class NavigationTest < ActiveSupport::TestCase
    test "exposes five groups in a fixed order" do
      assert_equal [ "Topics", "Meetings", "The Record", "The Machine", "Site" ],
                   Admin::Navigation::GROUPS.map(&:title)
    end

    test "every item's path helper resolves to a real route" do
      helpers = Rails.application.routes.url_helpers

      Admin::Navigation.items.each do |item|
        assert_respond_to helpers, item.path_helper,
          "#{item.label}: no route helper named #{item.path_helper}"
        path = helpers.public_send(item.path_helper)
        assert path.start_with?("/"), "#{item.label}: #{item.path_helper} did not return a path"
      end
    end

    test "every item's path is recognisable and routes to an admin controller" do
      helpers = Rails.application.routes.url_helpers

      Admin::Navigation.items.each do |item|
        path = helpers.public_send(item.path_helper)
        recognised = Rails.application.routes.recognize_path(path, method: :get)
        assert recognised[:controller].start_with?("admin/"),
          "#{item.label}: #{path} routes to #{recognised[:controller]}, not an admin controller"
      end
    end

    test "each item's controller matches the controller its path routes to" do
      helpers = Rails.application.routes.url_helpers

      Admin::Navigation.items.each do |item|
        path = helpers.public_send(item.path_helper)
        recognised = Rails.application.routes.recognize_path(path, method: :get)
        expected = recognised[:controller].split("/").last
        assert_equal expected, item.controller,
          "#{item.label}: declared controller #{item.controller.inspect} but path routes to #{expected.inspect}"
      end
    end

    test "every item has a non-blank description for the dashboard" do
      Admin::Navigation.items.each do |item|
        assert item.description.present?, "#{item.label} has no description"
      end
    end

    test "labels are unique" do
      labels = Admin::Navigation.items.map(&:label)
      assert_equal labels.uniq, labels
    end

    test "GROUPS and each group's items array are frozen" do
      assert Admin::Navigation::GROUPS.frozen?, "GROUPS is not frozen"

      Admin::Navigation::GROUPS.each do |group|
        assert group.items.frozen?, "#{group.title} group's items array is not frozen"
      end
    end
  end
end
