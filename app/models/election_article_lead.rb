class ElectionArticleLead < ApplicationRecord
  def questionnaire
    { "kind" => "article", "short_title" => "HTR candidate questionnaire",
      "title" => source_url.split("/")[-2].tr("-", " ").upcase_first,
      "publisher" => "Manitowoc Herald Times Reporter", "url" => source_url,
      "published_on" => published_on.iso8601, "link_label" => "Open HTR article",
      "section" => "City Council candidate questions and answers.", "body_selector" => "article .gnt_ar_b",
      "named_profiles" => true }
  end
end
