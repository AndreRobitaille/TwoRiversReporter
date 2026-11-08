require "test_helper"
require_relative "../support/member_campaign_scenario"

class CampaignStatementPublicationTest < ActiveJob::TestCase
  include MemberCampaignScenario

  setup { setup_member_campaign }

  test "one shared source links all known participants without creating offices or repeating analysis" do
    assert_no_difference [ "Member.count", "MemberPosition.count", "CommitteeMembership.count" ] do
      analyze_member_campaign
    end
    assert_equal 5, CampaignStatement.where(status: "accepted").count
    assert_equal [ 2, 2, 1 ], [ @jordan, @taylor, @morgan ].map { |member| CampaignStatement.current_for(member).size }
    statement = @taylor.campaign_statements.order(:sequence).first
    assert_equal "Taylor Example", statement.data.fetch("source_name")
    assert_equal "If grant funding is available.", statement.data.fetch("conditions")
    assert_equal Campaigns::PublishStatements::VALIDATION_METHOD, statement.validation_method
    assert_not_nil statement.validated_at
    before = CampaignStatement.order(:id).pluck(:id, :updated_at)
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Publication reuse must not call AI" }) do
      ExtractCampaignSourceJob.perform_now(@source.id)
    end
    assert_equal before, CampaignStatement.order(:id).pluck(:id, :updated_at)
    assert_equal 1, @calls.size
  end

  test "unknown and ambiguous people stay unresolved while known statements publish and later identity repair reuses extraction" do
    @morgan.destroy!
    conflicting = Member.create!(name: "Taylor Example")
    count = Member.count
    analyze_member_campaign
    assert_equal count, Member.count
    assert_equal 2, CampaignStatement.where(status: "accepted").count
    assert_equal({ "ambiguous_person" => 2, "unknown_person" => 1 }, CampaignStatement.where(status: "unresolved").group(:exception).count)
    assert_empty CampaignStatement.current_for(@taylor)
    assert_empty CampaignStatement.current_for(conflicting)

    conflicting.merge_into!(@taylor)
    @morgan = Member.create!(name: "Morgan Example")
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Identity repair must reuse extraction" }) do
      ExtractCampaignSourceJob.perform_now(@source.id)
    end
    assert_equal 5, CampaignStatement.where(status: "accepted").count
    assert_equal [ 2, 2, 1 ], [ @jordan, @taylor, @morgan ].map { |member| CampaignStatement.current_for(member).size }
    assert_equal 1, @calls.size
  end

  test "a missing passage prevents only that statement from publishing" do
    data = campaign_response_data
    data.fetch("participants").first.fetch("answers").last.fetch("statements").sole["supporting_quote"] = "Unsupported promise"
    analyze_member_campaign(content: data.to_json)
    assert_equal 4, CampaignStatement.where(status: "accepted").count
    assert_equal "unresolved_source_passage", CampaignStatement.where(status: "unresolved").sole.exception
    assert_equal [ 1, 2, 1 ], [ @jordan, @taylor, @morgan ].map { |member| CampaignStatement.current_for(member).size }
  end
end
