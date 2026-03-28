class PromptTemplate < ApplicationRecord
  has_many :versions, class_name: "PromptVersion", dependent: :destroy

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  validates :instructions, presence: true
  validates :model_tier, inclusion: { in: %w[default lightweight] }

  attr_accessor :editor_note

  after_save :create_version_if_changed

  def interpolate(context = {}, allow_missing: false, **kwargs)
    replace_placeholders(instructions, context.merge(kwargs), allow_missing: allow_missing)
  end

  def interpolate_system_role(context = {}, allow_missing: false, **kwargs)
    replace_placeholders(system_role || "", context.merge(kwargs), allow_missing: allow_missing)
  end

  private

  def replace_placeholders(text, context, allow_missing: false)
    text.gsub(/\{\{(\w+)\}\}/) do
      key = $1.to_sym
      if context.key?(key)
        context[key].to_s
      elsif allow_missing
        "{{#{$1}}}"
      else
        raise KeyError, "Missing placeholder: {{#{$1}}}"
      end
    end
  end

  def create_version_if_changed
    return unless saved_change_to_instructions? || saved_change_to_system_role? || saved_change_to_model_tier?

    versions.create!(
      system_role: system_role,
      instructions: instructions,
      model_tier: model_tier,
      editor_note: editor_note
    )

    self.editor_note = nil
  end
end
