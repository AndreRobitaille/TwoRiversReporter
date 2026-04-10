module Admin
  class SearchesController < BaseController
    def index
      @query = params[:q].to_s.strip
      return if @query.blank?

      @kb_results = retrieve_kb_results
      @document_results = retrieve_document_results

      if params[:ask_ai].present? && @kb_results.any?
        @numbered_context = build_numbered_context(@kb_results)
        @ai_answer = Ai::OpenAiService.new.answer_question(@query, @numbered_context)
      end
    end

    private

    def retrieve_kb_results
      RetrievalService.new.retrieve_context(@query, limit: 10)
    end

    def retrieve_document_results
      MeetingDocument.search(@query)
                     .includes(:meeting)
                     .select(
                       "meeting_documents.*",
                       "ts_headline('english', meeting_documents.extracted_text, websearch_to_tsquery('english', #{MeetingDocument.connection.quote(@query)}), 'MaxWords=35, MinWords=15, StartSel=<mark>, StopSel=</mark>') AS headline_excerpt"
                     )
                     .limit(10)
    end

    def build_numbered_context(results)
      results.each_with_index.map do |result, i|
        chunk = result[:chunk]
        source = chunk.knowledge_source
        label = source_label(source)
        "[#{i + 1}] #{label}\n#{chunk.content}"
      end
    end

    def source_label(source)
      date_suffix = source.stated_at ? " (#{source.stated_at})" : ""
      case source.origin
      when "manual"
        "[ADMIN NOTE: #{source.title}#{date_suffix}]"
      when "extracted"
        "[DOCUMENT-DERIVED: #{source.title}#{date_suffix}]"
      when "pattern"
        "[PATTERN-DERIVED: #{source.title}#{date_suffix}]"
      else
        "[#{source.title}#{date_suffix}]"
      end
    end
  end
end
