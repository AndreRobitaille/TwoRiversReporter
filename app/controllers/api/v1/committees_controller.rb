module Api
  module V1
    class CommitteesController < Api::BaseController
      def index
        render_collection(ResidentContent::CommitteeDirectory.new.call) { |record| serializer.committee_reference(record) }
      end

      def show
        committee = Committee.includes(committee_memberships: [ :committee, { member: :current_member_positions } ]).find_by!(slug: params[:slug])
        render_data(serializer.committee_detail(committee))
      end
    end
  end
end
