require "test_helper"
require "minitest/mock"

class Topics::GenerateDescriptionJobTest < ActiveJob::TestCase
  test "generates and saves description for topic with agenda items" do
    topic = Topic.create!(name: "lakefront development", status: "approved")

    meetings = 3.times.map do |i|
      Meeting.create!(
        body_name: "City Council", meeting_type: "Regular",
        starts_at: (i + 1).days.ago, status: "agenda_posted",
        detail_page_url: "http://example.com/m/desc-#{i}"
      )
    end

    meetings.each_with_index do |meeting, i|
      item = AgendaItem.create!(
        meeting: meeting, number: "1",
        title: "Lakefront item #{i}", summary: "Discussion #{i}",
        order_index: 1
      )
      AgendaItemTopic.create!(agenda_item: item, topic: topic)
    end

    mock_service = Minitest::Mock.new
    mock_service.expect :generate_topic_description, "Plans for the city's lakefront area." do |context|
      context[:topic_name] == "lakefront development" &&
        context[:agenda_items].size == 3 &&
        context[:agenda_items].first[:title] == "Lakefront item 0"
    end

    Ai::OpenAiService.stub :new, mock_service do
      Topics::GenerateDescriptionJob.perform_now(topic.id)
    end

    topic.reload
    assert_equal "Plans for the city's lakefront area.", topic.description
    assert_not_nil topic.description_generated_at
    mock_service.verify
  end

  test "skips topic with recent description_generated_at" do
    topic = Topic.create!(
      name: "water infrastructure", status: "approved",
      description: "Old AI description",
      description_generated_at: 1.day.ago
    )

    # AI should NOT be called
    Topics::GenerateDescriptionJob.perform_now(topic.id)

    topic.reload
    assert_equal "Old AI description", topic.description
  end

  test "regenerates if description_generated_at older than threshold" do
    topic = Topic.create!(
      name: "park improvements", status: "approved",
      description: "Stale AI description",
      description_generated_at: 91.days.ago
    )

    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.ago, status: "agenda_posted",
      detail_page_url: "http://example.com/m/regen-1"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Park work", order_index: 1)
    AgendaItemTopic.create!(agenda_item: item, topic: topic)

    mock_service = Minitest::Mock.new
    mock_service.expect :generate_topic_description, "Updated park description." do |context|
      context[:topic_name] == "park improvements"
    end

    Ai::OpenAiService.stub :new, mock_service do
      Topics::GenerateDescriptionJob.perform_now(topic.id)
    end

    topic.reload
    assert_equal "Updated park description.", topic.description
    assert_in_delta Time.current.to_f, topic.description_generated_at.to_f, 5.0
    mock_service.verify
  end

  test "skips if AI returns nil" do
    topic = Topic.create!(name: "noise ordinance", status: "approved")

    mock_service = Minitest::Mock.new
    mock_service.expect :generate_topic_description, nil do |context|
      true
    end

    Ai::OpenAiService.stub :new, mock_service do
      Topics::GenerateDescriptionJob.perform_now(topic.id)
    end

    topic.reload
    assert_nil topic.description
    assert_nil topic.description_generated_at
    mock_service.verify
  end

  test "does not overwrite admin-edited description" do
    topic = Topic.create!(
      name: "senior center", status: "approved",
      description: "Admin wrote this by hand",
      description_generated_at: nil
    )

    # AI should NOT be called
    Topics::GenerateDescriptionJob.perform_now(topic.id)

    topic.reload
    assert_equal "Admin wrote this by hand", topic.description
  end
end
