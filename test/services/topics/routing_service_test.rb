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
      Topic.create!(name: "former hamilton site", status: "approved")

      topic = Topics::RoutingService.call(
        "Downtown Redevelopment",
        document_text: "former hamilton site"
      )

      assert_equal reusable, topic
    end

    test "exact alias resolution wins before unsafe routing" do
      canonical = Topic.create!(name: "former hamilton site", status: "approved")
      TopicAlias.create!(name: "hamilton site redevelopment", topic: canonical)

      topic = Topics::RoutingService.call(
        "Hamilton Site Redevelopment",
        item_title: "Redevelopment",
        document_text: "rezoning"
      )

      assert_equal canonical, topic
    end

    test "unsafe redevelopment label routes to former hamilton site when context is strong" do
      former_hamilton = Topic.create!(name: "former hamilton site", status: "approved")

      topic = Topics::RoutingService.call(
        "Redevelopment",
        item_title: "Former Hamilton property",
        item_summary: "fischer visioning for the former hamilton site",
        meeting_body_name: "planning commission",
        document_text: "historic former hamilton site"
      )

      assert_equal former_hamilton, topic
    end

    test "unrelated downtown parcel rezoning does not route to former hamilton site" do
      Topic.create!(name: "former hamilton site", status: "approved")

      topic = Topics::RoutingService.call(
        "Redevelopment",
        item_title: "Downtown parcel rezoning",
        item_summary: "downtown redevelopment review",
        meeting_body_name: "planning commission",
        document_text: "site plan review"
      )

      assert_nil topic
    end

    test "existing topics containing former hamilton site do not route without Hamilton context" do
      Topic.create!(name: "former hamilton site", status: "approved")

      topic = Topics::RoutingService.call(
        "Redevelopment",
        existing_topics: ["former hamilton site"]
      )

      assert_nil topic
    end

    test "unsafe redevelopment label does not route on bare hamilton context" do
      Topic.create!(name: "former hamilton site", status: "approved")

      topic = Topics::RoutingService.call(
        "Redevelopment",
        document_text: "Hamilton"
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
