require "test_helper"

class Admin::TopicContextUpdatesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "context-editor@example.com", status: "active", admin: true)
    sign_in_as_admin(@admin)
    @topic = Topic.create!(name: "context water project", description: "Existing description", status: "approved")
    @identity = @topic.attributes.slice("id", "name", "canonical_name", "slug", "description", "status")
    get admin_topic_path(@topic)
    assert_response :success
    assert_select "textarea[name='topic[source_notes]']"
  end

  %w[html turbo_stream json].each do |format|
    test "#{format} saves changed context with author and time then clears provenance" do
      travel_to Time.current.change(usec: 0) do
        update_context(format, source_notes: "Distinctive first neighborhood observation", source_type: "admin_observation",
          added_by: "forged-editor@example.com", added_at: 10.years.ago)
        assert_update_success(format)
        assert_persisted_context("Distinctive first neighborhood observation", @admin.email_address, Time.current)
        assert_equal "admin_observation", @topic.source_type

        travel 1.minute
        next_editor = User.create!(email_address: "next-context-editor@example.com", status: "active", admin: true)
        sign_in_as_admin(next_editor)
        update_context(format, source_notes: "Distinctive revised neighborhood observation")
        assert_update_success(format)
        assert_persisted_context("Distinctive revised neighborhood observation", next_editor.email_address, Time.current)

        update_context(format, source_notes: "")
        assert_update_success(format)
        assert_equal "", @topic.reload.source_notes
        assert_nil @topic.added_by
        assert_nil @topic.added_at
        assert_equal @identity, @topic.attributes.slice(*@identity.keys)
      end
    end

    test "#{format} unchanged context retains its original author and time" do
      original_time = 2.days.ago.change(usec: 0)
      @topic.update!(source_notes: "Existing context", added_by: "original-editor@example.com", added_at: original_time)

      update_context(format, source_notes: "Existing context")

      assert_update_success(format)
      assert_persisted_context("Existing context", "original-editor@example.com", original_time)
    end

    test "#{format} validation failure leaves context and provenance unchanged" do
      original_time = 2.days.ago.change(usec: 0)
      @topic.update!(source_notes: "Existing context", added_by: "original-editor@example.com", added_at: original_time)
      snapshot = @topic.reload.attributes

      assert_no_difference "TopicReviewEvent.count" do
        update_context(format, source_notes: "Unsaved context canary", name: "")
      end

      assert_response :unprocessable_entity
      assert_equal snapshot, @topic.reload.attributes
      if format == "json"
        assert_equal false, response.parsed_body["success"]
        assert_not_empty response.parsed_body["errors"]
      elsif format == "html"
        assert_select ".flash--danger", text: /Name/
      else
        assert_select "turbo-stream .text-danger", text: /Name/
      end
      get admin_topic_path(@topic)
      assert_response :success
      assert_select "textarea[name='topic[source_notes]']", text: "Existing context"
    end
  end

  %w[anonymous member disabled pending no_passkey].each do |actor|
    test "#{actor} cannot change context or provenance after allowed admin access" do
      reset!
      unless actor == "anonymous"
        user = User.create!(email_address: "#{actor}-context@example.com", admin: actor != "member",
          status: actor == "pending" ? "pending" : "active",
          disabled_at: actor.in?(%w[disabled pending]) ? Time.current : nil)
        sign_in_as(user)
        user.passkey_credentials.delete_all if actor == "no_passkey"
      end
      snapshot = @topic.reload.attributes

      %w[html turbo_stream json].each do |format|
        assert_no_difference "TopicReviewEvent.count" do
          update_context(format, source_notes: "Denied notes canary", added_by: "forged@example.com")
        end
        assert_response :redirect
        assert_equal snapshot, @topic.reload.attributes
      end
    end
  end

  private

    def update_context(format, **attributes)
      patch admin_topic_path(@topic, format: format == "html" ? nil : format),
        params: { topic: attributes }, headers: { "Referer" => admin_topic_url(@topic) }
    end

    def assert_update_success(format)
      case format
      when "html"
        assert_redirected_to admin_topic_url(@topic)
      when "turbo_stream"
        assert_response :success
        assert_equal "text/vnd.turbo-stream.html", response.media_type
        assert_select "turbo-stream[action=replace][target=?]", ActionView::RecordIdentifier.dom_id(@topic)
      when "json"
        assert_response :success
        assert_equal true, response.parsed_body["success"]
      end
    end

    def assert_persisted_context(notes, author, time)
      @topic.reload
      assert_equal notes, @topic.source_notes
      assert_equal author, @topic.added_by
      assert_equal time, Time.parse(@topic.added_at)
      assert_equal @identity, @topic.attributes.slice(*@identity.keys)
      get admin_topic_path(@topic)
      assert_response :success
      assert_select "textarea[name='topic[source_notes]']", text: notes
    end
end
