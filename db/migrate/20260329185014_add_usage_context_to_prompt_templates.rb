class AddUsageContextToPromptTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :prompt_templates, :usage_context, :text
  end
end
