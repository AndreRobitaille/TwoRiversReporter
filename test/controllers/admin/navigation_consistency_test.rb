require "test_helper"

module Admin
  class NavigationConsistencyTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "nav-admin@example.com", admin: true)
      sign_in_as_admin(@admin)
    end

    test "sidebar links to every navigation item" do
      get admin_root_url
      assert_response :success

      Admin::Navigation.items.each do |item|
        path = Rails.application.routes.url_helpers.public_send(item.path_helper)
        assert_select "nav.adm-sidebar a[href=?]", path, text: item.label
      end
    end

    test "sidebar shows every group heading" do
      get admin_root_url

      Admin::Navigation::GROUPS.each do |group|
        assert_select "nav.adm-sidebar .adm-sidebar__group", text: group.title
      end
    end

    test "the current section's link is marked as the current page" do
      get admin_topics_url
      assert_response :success

      assert_select "nav.adm-sidebar a[aria-current=page]", count: 1, text: "All Topics"
    end
  end
end
