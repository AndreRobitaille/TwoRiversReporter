// app/javascript/controllers/prompt_editor_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]

  showTab(event) {
    const tabName = event.params.tab
    this.panelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.tab !== tabName)
    })

    // Update tab button active states
    this.element.querySelectorAll(".tab").forEach(tab => {
      tab.classList.toggle("active", tab.dataset.promptEditorTabParam === tabName)
    })
  }

  togglePlaceholders(event) {
    const button = event.currentTarget
    const list = button.nextElementSibling
    const expanded = button.getAttribute("aria-expanded") === "true"

    button.setAttribute("aria-expanded", !expanded)
    list.classList.toggle("visible")
  }

  async loadDiff(event) {
    const url = event.params.url
    const versionId = event.params.version
    const diffRow = document.getElementById(`diff-row-${versionId}`)
    const diffContent = document.getElementById(`diff-content-${versionId}`)

    if (diffRow.classList.contains("hidden")) {
      const response = await fetch(url, {
        headers: { "Accept": "text/html" }
      })
      const html = await response.text()
      // Use template element + replaceChildren for safe DOM insertion
      // (template.innerHTML sets content on a detached DocumentFragment, not the live DOM)
      const tmpl = document.createElement("template")
      tmpl.innerHTML = html
      diffContent.replaceChildren(tmpl.content)
      diffRow.classList.remove("hidden")
    } else {
      diffRow.classList.add("hidden")
    }
  }

  restore(event) {
    const systemRole = event.params.systemRole
    const instructions = event.params.instructions
    const modelTier = event.params.modelTier

    const systemRoleField = document.querySelector("textarea[name='prompt_template[system_role]']")
    const instructionsField = document.querySelector("textarea[name='prompt_template[instructions]']")
    const modelTierField = document.querySelector("select[name='prompt_template[model_tier]']")

    if (systemRoleField) systemRoleField.value = systemRole || ""
    if (instructionsField) instructionsField.value = instructions || ""
    if (modelTierField) modelTierField.value = modelTier || "default"

    // Switch to editor tab
    this.showTab({ params: { tab: "editor" } })

    // Scroll to top of form
    if (systemRoleField) systemRoleField.scrollIntoView({ behavior: "smooth", block: "start" })
  }
}
