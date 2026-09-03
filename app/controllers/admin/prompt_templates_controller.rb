class Admin::PromptTemplatesController < Admin::BaseController
  before_action :set_template, only: [ :edit, :update, :diff, :test_run ]

  def index
    @templates = PromptTemplate.order(:name)
  end

  def edit
    @versions = @template.versions.recent.limit(20)
    @examples = load_diverse_examples(@template.key)
    @evaluation_models = Ai::PromptEvaluator::MODEL_OPTIONS
  end

  def update
    @template.editor_note = params[:prompt_template][:editor_note]

    if @template.update(template_params)
      redirect_to edit_admin_prompt_template_path(@template), notice: "Prompt updated."
    else
      @versions = @template.versions.recent.limit(20)
      render :edit, status: :unprocessable_entity
    end
  end

  def diff
    version = @template.versions.find(params[:version_id])
    current_text = @template.instructions || ""
    version_text = version.instructions || ""

    @diff = Diffy::Diff.new(version_text, current_text, context: 3)
    @version = version

    render partial: "version_diff", locals: { diff: @diff, version: version }
  end

  def test_run
    @run = PromptRun.find_by(id: params[:prompt_run_id])
    unless @run
      head :not_found
      return
    end

    begin
      result = Ai::PromptEvaluator.new.evaluate(
        run: @run,
        template: @template,
        model_selection: params.fetch(:evaluation_model, "template_tier"),
        reasoning_effort: params.fetch(:reasoning_effort, "none"),
        system_role: params[:system_role].to_s,
        instructions: params[:instructions].to_s
      )
      @error = nil
    rescue => e
      result = nil
      @error = "Evaluation error: #{e.message}"
    end

    render partial: "test_comparison", locals: {
      original: @run.response_body,
      result: result,
      error: @error,
      run: @run
    }
  end

  private

  def set_template
    @template = PromptTemplate.find(params[:id])
  end

  def template_params
    params.require(:prompt_template).permit(:system_role, :instructions, :model_tier)
  end

  def load_diverse_examples(template_key)
    runs = PromptRun.for_template(template_key).recent.limit(10).to_a
    return runs if runs.size <= 5

    # Prefer diversity: one per source, fill remaining with recency
    grouped = runs.group_by { |r| [ r.source_type, r.source_id ] }
    diverse = grouped.values.map(&:first).sort_by(&:created_at).reverse
    diverse.first(5)
  end
end
