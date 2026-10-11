require "test_helper"

class AdminMaintenanceAccessTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "maintenance-access-admin@example.com", status: "active", admin: true)
    sign_in_as(@admin)
    @topic = Topic.create!(name: "maintenance protected canonical")
    @alias = @topic.topic_aliases.create!(name: "maintenance protected alias")
    @blocklist = TopicBlocklist.create!(name: "maintenance protected block", reason: "Existing block")
    @redirect = Redirect.create!(source_path: "/maintenance-protected-old", destination: "/about")
  end

  test "eligible admin sees the supported controls and unsupported URLs fail without changes" do
    get admin_topic_path(@topic)
    assert_response :success
    assert_select "form[action=?]", flip_alias_admin_topic_path(@topic)
    get admin_topic_blocklists_path
    assert_response :success
    assert_select "form[action=?]", admin_topic_blocklists_path
    assert_select "form[action=?]", admin_topic_blocklist_path(@blocklist)
    get admin_redirects_path
    assert_response :success
    assert_select "a[href=?]", new_admin_redirect_path
    assert_select "a[href=?]", edit_admin_redirect_path(@redirect)

    unsupported_requests.each do |method, path|
      public_send(method, path)
      assert_response :not_found, "#{method.upcase} #{path} must be explicitly unsupported"
    end
    # With no new action, this path reaches show(id: "new") and uses the
    # existing admin missing-record redirect. Keep that established behavior.
    get "/admin/topics/new"
    assert_redirected_to root_path
    assert_equal "That record could not be found.", flash[:alert]
    assert_equal "maintenance protected canonical", @topic.reload.name
    assert_equal "Existing block", @blocklist.reload.reason
    assert_equal "/about", @redirect.reload.destination
  end

  test "failed blocklist creation exposes the existing validation alert and leaves records intact" do
    before = @blocklist.attributes
    post admin_topic_blocklists_path, params: { topic_blocklist: { name: "", reason: "Invalid synthetic entry" } }
    assert_redirected_to admin_topic_blocklists_path
    follow_redirect!
    assert_select ".flash--danger", text: /Name.*blank/
    assert_equal before, @blocklist.reload.attributes
    assert_not TopicBlocklist.exists?(reason: "Invalid synthetic entry")
  end

  %w[anonymous member disabled pending rejected no_passkey].each do |actor|
    test "#{actor} cannot read or mutate the maintenance records" do
      # Establish allowed access to these exact records before changing actor.
      get admin_topic_path(@topic)
      assert_response :success
      get admin_topic_blocklists_path
      assert_select "form[action=?]", admin_topic_blocklist_path(@blocklist)
      get edit_admin_redirect_path(@redirect)
      assert_select "input[name='redirect[destination]'][value='/about']"
      before = [ @topic, @alias, @blocklist, @redirect ].map(&:attributes)
      reset!
      expected = new_public_session_path
      unless actor == "anonymous"
        user = User.create!(email_address: "maintenance-#{actor}@example.com", status: actor.in?(%w[pending rejected]) ? actor : "active", admin: actor != "member")
        user.update!(disabled_at: Time.current) if actor == "disabled"
        if actor == "no_passkey"
          sign_in_with_session(user.sessions.create!(ip_address: "127.0.0.1", ip_prefix: NetworkPrefix.for("127.0.0.1"),
            device_fingerprint: DeviceFingerprint.for(nil), reauthenticated_at: Time.current, last_seen_at: Time.current))
          expected = settings_security_path
        else
          sign_in_as(user)
          expected = root_path if actor == "member"
        end
      end
      [ admin_topic_path(@topic), admin_topic_blocklists_path, edit_admin_redirect_path(@redirect) ].each do |path|
        get path
        assert_redirected_to expected
      end
      post flip_alias_admin_topic_path(@topic)
      assert_redirected_to expected
      post admin_topic_blocklists_path, params: { topic_blocklist: { name: "denied new block" } }
      assert_redirected_to expected
      delete admin_topic_blocklist_path(@blocklist)
      assert_redirected_to expected
      post admin_redirects_path, params: { redirect: { source_path: "/denied-new-redirect", destination: "/" } }
      assert_redirected_to expected
      patch admin_redirect_path(@redirect), params: { redirect: { destination: "/meetings" } }
      assert_redirected_to expected
      delete admin_redirect_path(@redirect)
      assert_redirected_to expected
      assert_equal before, [ @topic, @alias, @blocklist, @redirect ].map { |record| record.reload.attributes }
      assert_not TopicBlocklist.exists?(name: "denied new block")
      assert_not Redirect.exists?(source_path: "/denied-new-redirect")
      assert_empty TopicReviewEvent.where(topic: @topic)
      get admin_topic_path(@topic)
      assert_redirected_to expected
    end
  end

  private

    def unsupported_requests
      [ [ :post, "/admin/topics" ], [ :get, "/admin/topics/#{@topic.id}/edit" ],
        [ :delete, "/admin/topics/#{@topic.id}" ], [ :get, "/admin/topic_blocklists/new" ],
        [ :get, "/admin/topic_blocklists/#{@blocklist.id}/edit" ], [ :get, "/admin/topic_blocklists/#{@blocklist.id}" ],
        [ :patch, "/admin/topic_blocklists/#{@blocklist.id}" ], [ :put, "/admin/topic_blocklists/#{@blocklist.id}" ],
        [ :get, "/admin/redirects/#{@redirect.id}" ] ]
    end
end
