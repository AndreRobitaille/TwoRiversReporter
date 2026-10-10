module Api
  module V1
    # Child records can change without touching their meeting/topic. These
    # batched timestamps describe available content, independent of event dates.
    class ContentUpdates
      DOCUMENT_TYPES = %w[agenda_pdf agenda_html packet_pdf packet_html minutes_pdf minutes_html transcript].freeze

      def initialize
        @metadata = {}
      end

      def preload(records)
        missing = records.select { |record| !@metadata.key?([ record.class.name, record.id ]) }
        meetings = missing.grep(Meeting)
        topics = missing.grep(Topic)
        preload_meetings(meetings) if meetings.any?
        preload_topics(topics) if topics.any?
      end

      def for(record)
        preload([ record ])
        @metadata.fetch([ record.class.name, record.id ])
      end

      private

        def preload_meetings(records)
          ids = records.map(&:id)
          documents = MeetingDocument.where(meeting_id: ids, document_type: DOCUMENT_TYPES)
            .select("DISTINCT ON (meeting_id, document_type) meeting_id, document_type, updated_at",
              "document_type = 'transcript' AND NULLIF(btrim(extracted_text), '') IS NOT NULL AS transcript_available")
            .order(:meeting_id, :document_type, created_at: :desc, id: :desc).group_by(&:meeting_id)
          analyses = ResidentQueries.preferred_summaries.where(meeting_id: ids)
            .reselect("DISTINCT ON (meeting_id) meeting_id, updated_at").map { |row| [ row.meeting_id, row.updated_at ] }.to_h
          agenda = AgendaItem.substantive.where(meeting_id: ids).group(:meeting_id).maximum(:updated_at)
          records.each do |record|
            docs = documents.fetch(record.id, [])
            document_time = docs.map(&:updated_at).max
            analysis_time = record.cancelled? ? nil : analyses[record.id]
            @metadata[[ record.class.name, record.id ]] = {
              updated_at: [ record.updated_at, document_time, analysis_time, agenda[record.id] ].compact.max,
              last_document_updated_at: document_time, last_analysis_updated_at: analysis_time,
              available_document_types: docs.map(&:document_type).sort,
              has_analysis: analysis_time.present?, has_transcript: docs.any? { |doc| doc[:transcript_available] }
            }
          end
        end

        def preload_topics(records)
          ids = records.map(&:id)
          analyses = TopicBriefing.where(topic_id: ids).group(:topic_id).maximum(:updated_at)
          appearances = TopicAppearance.where(topic_id: ids).group(:topic_id).maximum(:updated_at)
          aliases = TopicAlias.where(topic_id: ids).group(:topic_id).maximum(:updated_at)
          records.each do |record|
            @metadata[[ record.class.name, record.id ]] = {
              updated_at: [ record.updated_at, analyses[record.id], appearances[record.id], aliases[record.id] ].compact.max,
              last_analysis_updated_at: analyses[record.id], has_analysis: analyses[record.id].present?
            }
          end
        end
    end
  end
end
