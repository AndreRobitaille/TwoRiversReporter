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

  toggleRunCard(event) {
    const card = event.currentTarget.closest(".prompt-run-card")
    const body = card.querySelector(".prompt-run-body")
    const isExpanded = card.classList.contains("expanded")

    card.classList.toggle("expanded", !isExpanded)
    body.classList.toggle("hidden", isExpanded)
  }

  async testRun(event) {
    event.stopPropagation()
    const runId = event.params.runId
    const testUrl = event.params.testUrl
    const button = event.currentTarget
    const comparisonDiv = document.getElementById(`comparison-${runId}`)

    // Grab current form values (possibly edited, unsaved)
    const systemRole = document.querySelector("textarea[name='prompt_template[system_role]']")?.value || ""
    const instructions = document.querySelector("textarea[name='prompt_template[instructions]']")?.value || ""

    // Show loading state
    const originalText = button.textContent
    button.textContent = "Running..."
    button.disabled = true

    try {
      const response = await fetch(testUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Accept": "text/html",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        body: new URLSearchParams({
          prompt_run_id: runId,
          system_role: systemRole,
          instructions: instructions
        })
      })

      const html = await response.text()
      // Use template element + replaceChildren for safe DOM insertion
      // (template.innerHTML sets content on a detached DocumentFragment, not the live DOM)
      const tmpl = document.createElement("template")
      tmpl.innerHTML = html  // safe: sets on detached DocumentFragment, same pattern as loadDiff above
      comparisonDiv.replaceChildren(tmpl.content)
      comparisonDiv.classList.remove("hidden")
      comparisonDiv.scrollIntoView({ behavior: "smooth", block: "start" })
    } catch (err) {
      // Use safe textContent for error display
      const errorDiv = document.createElement("div")
      errorDiv.className = "test-comparison-error"
      errorDiv.textContent = `Request failed: ${err.message}`
      comparisonDiv.replaceChildren(errorDiv)
      comparisonDiv.classList.remove("hidden")
    } finally {
      button.textContent = originalText
      button.disabled = false
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
