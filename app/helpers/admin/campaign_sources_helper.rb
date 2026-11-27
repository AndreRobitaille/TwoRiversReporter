module Admin::CampaignSourcesHelper
  def questionnaire_review_reason(reason)
    case reason
    when "unknown_person" then "No Council member record matches this name. Check the article before linking these statements to anyone."
    when "ambiguous_person" then "More than one member record matches this name. Confirm who gave these answers."
    when "unresolved_question" then "The question could not be found in the saved answers. Check the source text."
    when "unresolved_source_passage" then "The supporting passage could not be verified in the saved answers."
    else "Compare these statements and their supporting passages with the original article."
    end
  end
end
