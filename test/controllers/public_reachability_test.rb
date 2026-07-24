require "test_helper"

class PublicReachabilityTest < ActionDispatch::IntegrationTest
  MODES = %w[open gated].freeze

  test "index pages are reachable anonymously in both modes" do
    MODES.each do |mode|
      set_access_mode(mode)

      [ root_path, topics_path, meetings_path, committees_path ].each do |path|
        get path
        assert_response :success, "#{path} should render anonymously in #{mode} mode"
      end
    end
  end

  test "detail pages are reachable anonymously in both modes" do
    meeting = Meeting.create!(body_name: "City Council Meeting", starts_at: 2.days.ago, detail_page_url: "https://example.com/meeting")
    topic = Topic.create!(name: "Reachability Topic", status: "approved")

    MODES.each do |mode|
      set_access_mode(mode)

      get meeting_path(meeting)
      assert_response :success, "meeting show should render anonymously in #{mode} mode"

      get topic_path(topic)
      assert_response :success, "topic show should render anonymously in #{mode} mode"
    end
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
