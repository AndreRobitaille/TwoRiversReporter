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

    test "the sidebar renders exactly one link per navigation item, no more and no fewer" do
      get admin_root_url
      assert_response :success

      # Direct children of nav.adm-sidebar with class adm-sidebar__link excludes
      # both the .adm-sidebar__brand link and the links nested inside
      # .adm-sidebar__foot (Public Site / Security / Sign Out), which are not
      # direct children of the nav. This guards against the partial hardcoding
      # a list that happens to match Admin::Navigation.items today: an extra
      # or missing link changes this count even if every existing item's
      # label/href still matches.
      assert_select "nav.adm-sidebar > a.adm-sidebar__link", count: Admin::Navigation.items.size
    end

    test "dashboard links to exactly the same items as the sidebar, and no others" do
      get admin_root_url
      assert_response :success

      expected = Admin::Navigation.items.map do |item|
        Rails.application.routes.url_helpers.public_send(item.path_helper)
      end.sort

      dashboard_links = css_select("main .adm-launcher a").map { |a| a["href"] }.sort

      assert_equal expected, dashboard_links,
        "dashboard and Admin::Navigation disagree — this is the exact drift the constant exists to prevent"
    end

    test "dashboard shows each item's description" do
      get admin_root_url

      Admin::Navigation.items.each do |item|
        assert_match item.description, response.body
      end
    end
  end
end
