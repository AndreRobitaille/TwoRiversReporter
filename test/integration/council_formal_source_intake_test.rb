require "test_helper"
require "minitest/mock"
require_relative "../support/council_formal_scenario"

class CouncilFormalSourceIntakeTest < ActionDispatch::IntegrationTest
  include CouncilFormalScenario

  setup do
    setup_formal_records
    sign_in_as_admin(@editor)
  end

  test "admin verification permits one source and a later correction withdraws stale public evidence" do
    attributes = formal_attributes.except(:verified_by, :verified_at, :subject_names)
      .merge(source_url: "https://example.test/second-case-record.pdf", subject_names_text: "#{@member.name}\n#{@peer.name}", verified_by_id: -1)
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Intake does not spend" }) do
      assert_enqueued_jobs 1, only: ExtractCouncilFormalRecordsJob do
        post admin_council_formal_sources_path, params: { council_formal_source: attributes, verified: "1" }
      end
    end
    source = CouncilFormalSource.order(:id).last
    assert_redirected_to admin_council_formal_source_path(source)
    assert_equal @editor.id, source.verified_by_id
    assert_equal [ @member.name, @peer.name ], source.subject_names
    assert_equal [ @period.period_key ], source.service_period_keys
    extract_formal(source)
    get member_path(@member)
    assert_select "[data-formal-event=filed]", count: 1
    patch admin_council_formal_source_path(source), params: { council_formal_source: { permitted_text: "The retained record needs editorial correction." } }
    assert_redirected_to admin_council_formal_source_path(source)
    assert_nil source.reload.verified_at
    get member_path(@member)
    assert_select "[data-formal-case]", count: 0
    assert_not_includes response.body, @filing_quote
    assert_equal 1, source.reviews.count
    get admin_council_formal_source_path(source, version: source.reviews.first.id)
    assert_response :success
    assert_includes response.body, "Viewing an earlier or unpublished analysis"
    assert_includes response.body, @filing_quote
    get admin_council_formal_source_path(@formal_source, version: source.reviews.first.id)
    assert_redirected_to root_path
    assert_not_includes response.body, @filing_quote
  end

  test "allowed admin can read private notes before reader and anonymous denial" do
    get admin_council_formal_source_path(@formal_source)
    assert_response :success
    assert_includes response.body, "PRIVATE COMPLAINANT CANARY"
    sign_in_as(User.create!(email_address: "formal-intake-reader@example.test", status: "active"))
    get admin_council_formal_source_path(@formal_source)
    assert_redirected_to root_path
    assert_not_includes response.body, "PRIVATE COMPLAINANT CANARY"
    original = @formal_source.attributes
    patch admin_council_formal_source_path(@formal_source), params: { council_formal_source: { title: "Unauthorized accusation" }, verified: "1" }
    assert_redirected_to root_path
    assert_equal original, @formal_source.reload.attributes
    delete public_session_path
    [ admin_council_formal_source_path(@formal_source), admin_council_formal_source_path(@formal_source, format: :json), new_admin_council_formal_source_path ].each do |path|
      get path
      assert_response :redirect
      assert_not_includes response.body, @formal_source.case_reference
      assert_not_includes response.body, "PRIVATE COMPLAINANT CANARY"
    end
  end

  test "missing source or service validation preserves the correction form" do
    patch admin_council_formal_source_path(@formal_source), params: { council_formal_source: { source_url: "", service_period_keys: [] }, verified: "1" }
    assert_response :unprocessable_entity
    assert_select "textarea[name='council_formal_source[permitted_text]']", text: @filing_quote
    assert @formal_source.reload.eligible?
  end
end
