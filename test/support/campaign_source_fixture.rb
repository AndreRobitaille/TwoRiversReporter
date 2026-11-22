module CampaignSourceFixture
  def campaign_article_attributes
    {
      title: "Synthetic candidate questionnaire", publisher: "Example Newspaper",
      source_url: "https://example.test/candidate-questionnaire", election_on: "2027-04-06",
      published_on: "2027-03-20", coverage: "full_article",
      body: Rails.root.join("test/fixtures/files/campaign_questionnaire.txt").read.strip
    }
  end
end
