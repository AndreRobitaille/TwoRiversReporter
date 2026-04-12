class Meeting < ApplicationRecord
  has_many :meeting_documents, dependent: :destroy
  has_many :agenda_items, dependent: :destroy
  has_many :topics, -> { distinct }, through: :agenda_items
  has_many :meeting_summaries, dependent: :destroy
  has_many :topic_summaries, dependent: :destroy
  has_many :motions, dependent: :destroy
  has_many :meeting_attendances, dependent: :destroy
  has_many :knowledge_sources, dependent: :nullify
  belongs_to :committee, optional: true

  validates :detail_page_url, presence: true, uniqueness: true

  scope :upcoming, -> { where("starts_at > ?", Time.current).order(starts_at: :asc) }
  scope :recent, -> { where("starts_at <= ?", Time.current).order(starts_at: :desc) }
  scope :in_window, ->(from, to) { where(starts_at: from..to) }

  MONTH_NAMES = {
    "january" => 1, "jan" => 1, "february" => 2, "feb" => 2,
    "march" => 3, "mar" => 3, "april" => 4, "apr" => 4,
    "may" => 5, "june" => 6, "jun" => 6,
    "july" => 7, "jul" => 7, "august" => 8, "aug" => 8,
    "september" => 9, "sep" => 9, "october" => 10, "oct" => 10,
    "november" => 11, "nov" => 11, "december" => 12, "dec" => 12
  }.freeze

  def self.search_multi(query)
    return none if query.blank?

    terms = query.strip.downcase

    # 1. Date detection — extract month/year from query
    date_scope = parse_date_filter(terms)

    # 2. Body name match
    body_matches = where("LOWER(body_name) LIKE ?", "%#{sanitize_sql_like(terms)}%")

    # 3. Topic name match
    topic_matches = joins(agenda_items: :topics)
      .where("LOWER(topics.name) LIKE ?", "%#{sanitize_sql_like(terms)}%")
      .distinct

    # 4. Document full-text match
    doc_ids = MeetingDocument.search(query).pluck(:meeting_id)
    doc_matches = doc_ids.any? ? where(id: doc_ids) : none

    # Union all sources
    combined_ids = (body_matches.pluck(:id) +
                    topic_matches.pluck(:id) +
                    doc_matches.pluck(:id) +
                    (date_scope ? date_scope.pluck(:id) : [])
                   ).uniq

    where(id: combined_ids)
      .includes(:committee, :meeting_documents, :meeting_summaries, agenda_items: :topics)
      .order(starts_at: :desc)
  end

  def self.parse_date_filter(terms)
    month = nil
    year = nil

    MONTH_NAMES.each do |name, num|
      if terms.include?(name)
        month = num
        break
      end
    end

    year = $1.to_i if terms =~ /\b(20\d{2})\b/

    return nil unless month || year

    if month && year
      start_date = Date.new(year, month, 1)
      where(starts_at: start_date.beginning_of_day..start_date.end_of_month.end_of_day)
    elsif year
      start_date = Date.new(year, 1, 1)
      where(starts_at: start_date.beginning_of_day..start_date.end_of_year.end_of_day)
    elsif month
      where("EXTRACT(MONTH FROM starts_at) = ?", month)
    end
  end

  private_class_method :parse_date_filter

  def document_status
    # Avoid N+1 queries if loaded, otherwise load
    docs = association(:meeting_documents).loaded? ? meeting_documents : meeting_documents.load

    if docs.any? { |d| d.document_type == "minutes_pdf" }
      :minutes
    elsif docs.any? { |d| d.document_type == "packet_pdf" }
      :packet
    elsif docs.any? { |d| d.document_type == "transcript" }
      :transcript
    elsif docs.any? { |d| d.document_type == "agenda_pdf" }
      :agenda
    else
      :none
    end
  end
end
