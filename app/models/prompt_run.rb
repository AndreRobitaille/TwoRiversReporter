class PromptRun < ApplicationRecord
  belongs_to :source, polymorphic: true, optional: true

  validates :prompt_template_key, presence: true
  validates :ai_model, presence: true
  validates :response_body, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_template, ->(key) { where(prompt_template_key: key) }

  after_create :prune_old_runs

  # Display label for the source record (used in the examples tab)
  def source_label
    case source
    when Meeting
      "#{source.body_name} — #{source.starts_at&.strftime('%b %d, %Y')}"
    when Topic
      source.name
    else
      source_type.present? ? "#{source_type} ##{source_id}" : "No source"
    end
  end

  private

  def prune_old_runs
    old_ids = PromptRun
      .where(prompt_template_key: prompt_template_key)
      .order(created_at: :desc)
      .offset(10)
      .pluck(:id)

    PromptRun.where(id: old_ids).delete_all if old_ids.any?
  end
end
