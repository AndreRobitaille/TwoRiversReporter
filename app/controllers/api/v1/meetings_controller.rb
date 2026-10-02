module Api
  module V1
    class MeetingsController < Api::BaseController
      def index
        since, sort = update_filters(default_sort: "date")
        records = ResidentContent::MeetingSelection.catalog
        records = ResidentQueries.new(search_query).meetings(records) if search_query
        records = filter_updated_records(filter_meetings(records), since: since)
        if sort == "updated"
          records = updated_records(records)
        else
          records.sort_by! { |record| [ -(record.starts_at || Time.at(0)).to_i, -record.id ] }
        end
        serializer.remember_canonical(records)
        render_collection(records, preload: [ :meeting_summaries ]) { |record| serializer.meeting(record) }
      end

      def show
        render_data(serializer.meeting_detail(meeting, requested_id: params[:id]))
      end

      def agenda_items
        render_collection(serializer.agenda_items(meeting)) { |entry| entry }
      end

      def documents
        render_collection(serializer.resident_documents(meeting)) { |document| serializer.document_payload(document) }
      end

      def transcript
        document = meeting.latest_document("transcript")
        raise ActiveRecord::RecordNotFound unless document&.extracted_text.present?

        text = document.extracted_text
        checksum = Digest::SHA256.hexdigest(text)
        if (params[:document_id].present? && params[:document_id].to_s != document.id.to_s) ||
            (params[:checksum].present? && params[:checksum] != checksum)
          return render_error("transcript_changed", "The transcript changed. Restart from offset 0.", :conflict)
        end
        limit = integer_parameter(:limit, default: 20_000, maximum: 50_000)
        offset = integer_parameter(:offset, default: 0, minimum: 0)
        if offset.positive? && (params[:document_id].blank? || params[:checksum].blank?)
          raise ArgumentError, "Transcript continuation requires document_id and checksum. Follow links.next."
        end
        chunk = text[offset, limit] || ""
        next_url = if offset + chunk.length < text.length
          query = { offset: offset + chunk.length, limit: limit, document_id: document.id, checksum: checksum }.to_query
          serializer.url("/api/v1/meetings/#{meeting.id}/transcript?#{query}")
        end
        render_data(serializer.document_payload(document).merge(text: chunk, checksum: checksum,
          offset: offset, returned_chars: chunk.length, total_chars: text.length,
          source_notice: "Recording transcript; supplements official minutes and is not an official record."), links: { next: next_url })
      end

      private

        def meeting
          @meeting ||= serializer.canonical(Meeting.find(params[:id]))
        end

        def filter_meetings(records)
          if params[:committee_id].present?
            committee_id = integer_parameter(:committee_id, default: nil)
            records = records.select { |record| record.committee_id == committee_id }
          end
          %w[from to].each do |filter|
            next if params[filter].blank?

            date = Date.iso8601(params[filter].to_s)
            records = records.select do |record|
              record.starts_at && (filter == "from" ? record.starts_at.to_date >= date : record.starts_at.to_date <= date)
            end
          end
          if params[:status].present?
            raise ArgumentError, "Status must be scheduled or cancelled." unless %w[scheduled cancelled].include?(params[:status])
            cancelled = params[:status] == "cancelled"
            records = records.select { |record| record.cancelled? == cancelled }
          end
          records
        end
    end
  end
end
