class TopicAlias < ApplicationRecord
  belongs_to :topic

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_validation :normalize_name

  def normalize_name
    self.name = Topic.normalize_name(name)
  end

  before_save :lock_agenda_context_topics
  before_destroy :lock_agenda_context_topics, prepend: true
  after_save :withdraw_dependent_agenda_summaries
  after_destroy :withdraw_dependent_agenda_summaries

  private

  def lock_agenda_context_topics
    Topics::AgendaBriefingContext.lock_topics(topic_id, topic_id_in_database)
  end

  def withdraw_dependent_agenda_summaries
    Meetings::WithdrawAgendaSummaries.call(topic_ids: [ topic_id, topic_id_before_last_save ])
  end
end
