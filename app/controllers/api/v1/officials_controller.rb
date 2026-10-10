module Api
  module V1
    class OfficialsController < Api::BaseController
      def index
        render_collection(Member.includes(:current_member_positions).order(:name, :id)) { |record| serializer.official(record) }
      end

      def show
        render_data(serializer.official_detail(official))
      end

      def votes
        render_collection(ResidentContent::OfficialProfile.new(official).resident_votes) { |vote| serializer.vote_payload(vote) }
      end

      private

        def official
          @official ||= Member.includes(:current_member_positions, committee_memberships: :committee).find(params[:id])
        end
    end
  end
end
