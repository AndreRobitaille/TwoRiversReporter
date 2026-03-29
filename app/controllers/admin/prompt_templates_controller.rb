class Admin::PromptTemplatesController < Admin::BaseController
  before_action :set_template, only: [ :edit, :update, :diff, :test_run ]

  def index
    @templates = PromptTemplate.order(:name)
  end

  def edit
    @versions = @template.versions.recent.limit(20)
    @examples = load_diverse_examples(@template.key)
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

    edited_system_role = params[:system_role].to_s
    edited_instructions = params[:instructions].to_s

    # Re-interpolate with stored placeholder values
    placeholder_values = (@run.placeholder_values || {}).symbolize_keys
    begin
      new_system_role = replace_template_placeholders(edited_system_role, placeholder_values)
      new_user_prompt = replace_template_placeholders(edited_instructions, placeholder_values)
    rescue KeyError => e
      @error = "Placeholder error: #{e.message}"
      render partial: "test_comparison", locals: { original: @run.response_body, result: nil, error: @error, run: @run, duration_ms: nil, response_format: @run.response_format }
      return
    end

    messages = [
      (new_system_role.present? ? { role: "system", content: new_system_role } : nil),
      { role: "user", content: new_user_prompt }
    ].compact

    model = @template.model_tier == "lightweight" ? Ai::OpenAiService::LIGHTWEIGHT_MODEL : Ai::OpenAiService::DEFAULT_MODEL

    begin
      client = OpenAI::Client.new(access_token: Rails.application.credentials.openai_access_token || ENV["OPENAI_ACCESS_TOKEN"])

      chat_params = {
        model: model,
        messages: messages
      }
      chat_params[:response_format] = { type: @run.response_format } if @run.response_format.present?
      chat_params[:temperature] = @run.temperature if @run.temperature.present?

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = client.chat(parameters: chat_params)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      result = response.dig("choices", 0, "message", "content")
      @error = nil
    rescue => e
      result = nil
      @error = "API error: #{e.message}"
      duration_ms = nil
    end

    render partial: "test_comparison", locals: {
      original: @run.response_body,
      result: result,
      error: @error,
      run: @run,
      duration_ms: duration_ms,
      response_format: @run.response_format
    }
  end

  private

  def set_template
    @template = PromptTemplate.find(params[:id])
  end

  def template_params
    params.require(:prompt_template).permit(:system_role, :instructions, :model_tier)
  end

  def replace_template_placeholders(text, context)
    text.gsub(/\{\{(\w+)\}\}/) do
      key = $1.to_sym
      if context.key?(key)
        context[key].to_s
      else
        raise KeyError, "Missing placeholder: {{#{$1}}}"
      end
    end
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
