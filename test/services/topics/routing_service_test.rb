require "test_helper"

module Topics
  class RoutingServiceTest < ActiveSupport::TestCase
    setup do
      AgendaItemTopic.destroy_all
      TopicAlias.destroy_all
      Topic.destroy_all
      TopicBlocklist.destroy_all
    end

    test "exact reusable topic match wins before contextual routing" do
      reusable = Topic.create!(name: "downtown redevelopment", status: "approved")
      Topic.create!(name: "former hamilton site redevelopment", status: "approved")

      topic = Topics::RoutingService.call(
        "Downtown Redevelopment",
        context: { text: "former hamilton site" }
      )

      assert_equal reusable, topic
    end

    test "unsafe redevelopment label routes to former hamilton site when context is strong" do
      former_hamilton = Topic.create!(name: "former hamilton site", status: "approved")

      topic = Topics::RoutingService.call(
        "Redevelopment",
        context: { body_name: "Former Hamilton Site", text: "former hamilton site redevelopment" }
      )

      assert_equal former_hamilton, topic
    end

    test "unsafe redevelopment label does not route on bare hamilton context" do
      Topic.create!(name: "former hamilton site", status: "approved")

      topic = Topics::RoutingService.call(
        "Redevelopment",
        context: { text: "Hamilton" }
      )

      assert_nil topic
    end

    test "unsafe redevelopment label does not route without supporting context" do
      Topic.create!(name: "former hamilton site", status: "approved")

      topic = Topics::RoutingService.call("Redevelopment")

      assert_nil topic
    end
  end
end
