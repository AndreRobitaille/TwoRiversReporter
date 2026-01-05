class MeetingDocument < ApplicationRecord
  belongs_to :meeting
  has_many :extractions, dependent: :destroy
  has_one_attached :file

  after_save :update_search_vector, if: :saved_change_to_extracted_text?

  scope :search, ->(query) {
    where("search_vector @@ websearch_to_tsquery('english', ?)", query)
  }

  private

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
