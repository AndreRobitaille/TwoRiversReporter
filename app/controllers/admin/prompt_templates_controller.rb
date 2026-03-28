class Admin::PromptTemplatesController < Admin::BaseController
  before_action :set_template, only: [ :edit, :update, :diff ]

  def index
    @templates = PromptTemplate.order(:name)
  end

  def edit
    @versions = @template.versions.recent.limit(20)
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

  private

  def set_template
    @template = PromptTemplate.find(params[:id])
  end

  def template_params
    params.require(:prompt_template).permit(:system_role, :instructions, :model_tier)
  end
end
