require_relative "campaign_extraction_scenario"

module MemberCampaignScenario
  include CampaignExtractionScenario

  def setup_member_campaign
    setup_campaign_extraction
    @jordan = Member.create!(name: "Jordan Example")
    @taylor = Member.create!(name: "Taylor A. Example")
    @taylor.member_aliases.create!(name: "Taylor Example")
    @morgan = Member.create!(name: "Morgan Example")
  end

  def analyze_member_campaign(content: campaign_response_data.to_json)
    budget = campaign_budget
    with_campaign_transport(content: content) { ExtractCampaignSourceJob.perform_now(@source.id, budget_run_id: budget.id) }
  end
end
