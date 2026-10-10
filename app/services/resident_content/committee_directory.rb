module ResidentContent
  class CommitteeDirectory
    def call
      Committee.where(status: %w[active dormant]).includes(committee_memberships: :member).order(:name, :id)
        .reject { |committee| CommitteesController::EXCLUDED.include?(committee.name) }
        .reject { |committee| committee.name != "City Council" && committee.status == "dormant" && public_memberships(committee).empty? }
    end

    def public_memberships(committee)
      committee.committee_memberships.select { |membership|
        membership.ended_on.nil? && !%w[staff non_voting].include?(membership.role)
      }
    end
  end
end
