module Admin
  class CampaignStatementReviewsController < BaseController
    def update
      decision = params.expect(:decision)
      return head :bad_request unless decision.in?(%w[exclude restore])

      source = CampaignSource.find(params[:admin_campaign_source_id])
      excluded = decision == "exclude"
      statement = source.with_lock { review_statement(source, excluded) }
      redirect_to admin_campaign_source_path(source, from_year: params[:from_year], reviewed_member: statement.member_id, anchor: helpers.dom_id(statement)),
        notice: (excluded ? "Statement excluded from the campaign record." : "Statement restored to the campaign record."), status: :see_other
    end

    private

    def review_statement(source, excluded)
      extraction = source.current_version&.extraction
      raise ActiveRecord::RecordNotFound unless extraction&.status == "completed"

      statement = extraction.campaign_statements.where(status: "accepted").lock.find(params[:id])
      return statement if statement.excluded_at? == excluded

      statement.update!(excluded_at: excluded ? Time.current : nil)
      AuditEvent.record!(actor: Current.user, action: (excluded ? "campaign_statement_excluded" : "campaign_statement_restored"),
        subject: statement, label: statement.data.fetch("source_name"), request: request, metadata: { campaign_source_id: source.id })
      statement
    end
  end
end
