module Api
  module V1
    class HomeController < Api::BaseController
      def show
        selections = ResidentContent::HomeSelection.new.call
        render_data(selections.transform_values { |records|
          records.map { |record| record.is_a?(Meeting) ? serializer.meeting(record) : serializer.topic(record) }
        })
      end
    end
  end
end
