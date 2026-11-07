class MeetingDocument < ApplicationRecord
  belongs_to :meeting
  belongs_to :latest_text_version, class_name: "MeetingDocumentTextVersion", optional: true
  has_many :extractions, dependent: :destroy
  has_many :transcript_imports, dependent: :nullify
  has_many :source_versions, class_name: "MeetingDocumentVersion", dependent: :nullify
  has_one_attached :file

  after_save :update_search_vector, if: :saved_change_to_extracted_text?

  # Inspect the final transaction state: download and text publication replace
  # several related rows, and intermediate snapshots are not published sources.
  before_commit :withdraw_changed_source_analysis

  scope :search, ->(query) {
    where("search_vector @@ websearch_to_tsquery('english', ?)", query)
  }

  def current_source_version
    source_versions.find_by(version_key: MeetingDocumentVersion.key_for(self))
  end

  def current_text_version
    version = latest_text_version
    version if version && version.meeting_document_version_id == current_source_version&.id
  end

  private

  def withdraw_changed_source_analysis
    Meetings::SummaryPublication.with_lock(meeting_id, meeting_id_before_last_save) do
      Topics::WithdrawSourceBriefings.call(document_id: id, meeting_id: meeting_id)
      Meetings::WithdrawSourceSummaries.call(document_id: id)
    end
  end

  def update_search_vector
    Rails.logger.info "UPDATING SEARCH VECTOR for #{id}"
    return if extracted_text.blank?

    # Sanitize text to avoid PG::ProgramLimitExceeded for very long words
    safe_text = extracted_text.scan(/\S+/).reject { |word| word.length > 250 }.join(" ")

    # Execute SQL directly using update_all to ensure function execution
    # quote(safe_text) handles escaping the string literal for SQL
    sql = "to_tsvector('english', #{self.class.connection.quote(safe_text)})"

    # We must use update_all because update_columns might cast Arel.sql to string for tsvector type
    self.class.where(id: id).update_all("search_vector = #{sql}")
  rescue StandardError => e
    Rails.logger.error "Vector update failed: #{e.message}"
  end
end
