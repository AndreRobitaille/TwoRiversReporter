import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results", "targetId", "targetName", "selection", "submit", "preview"]
  static values = { url: String, actionName: String }

  connect() {
    this.debounceTimer = null
    this.requestToken = 0
    this.previewToken = 0
    this.selectedQuery = ""
  }

  search() {
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this.performSearch(), 150)
  }

  async performSearch() {
    const query = this.inputTarget.value.trim()
    const token = ++this.requestToken

    if (this.targetIdTarget?.value && query !== this.selectedQuery) {
      this.clearSelection()
      this.clearPreview()
    }

    if (query.length < 2) {
      this.resultsTarget.innerHTML = ""
      return
    }

    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", query)

    const response = await fetch(url.toString())
    const html = await response.text()

    if (token !== this.requestToken) return

    this.resultsTarget.innerHTML = html
  }

  selectCandidate(event) {
    const button = event.currentTarget
    this.selectedQuery = this.inputTarget.value.trim()
    if (this.hasTargetIdTarget) this.targetIdTarget.value = button.dataset.topicId
    if (this.hasTargetNameTarget) this.targetNameTarget.value = button.dataset.topicName
    if (this.hasSelectionTarget) this.selectionTarget.textContent = `Selected destination: ${button.dataset.topicName}`
    if (this.hasSubmitTarget) this.submitTarget.disabled = false
    this.refreshPreview(button.dataset)
  }

  clearSelection() {
    this.selectedQuery = ""
    if (this.hasTargetIdTarget) this.targetIdTarget.value = ""
    if (this.hasTargetNameTarget) this.targetNameTarget.value = ""
    if (this.hasSelectionTarget) this.selectionTarget.textContent = "Choose a topic from search results."
    if (this.hasSubmitTarget) this.submitTarget.disabled = true
    this.clearPreview()
  }

  clearPreview() {
    if (!this.hasPreviewTarget) return

    this.previewToken += 1

    const blankPreviewText = this.actionNameValue === "merge_away"
      ? "Choose a destination topic to preview the re-home."
      : this.actionNameValue === "topic_to_alias"
        ? "Choose a destination topic to preview the alias transfer. Any existing aliases on this topic will move with it."
        : "Choose a destination topic to preview the move."

    this.previewTarget.innerHTML = `<p class="text-secondary">${blankPreviewText}</p>`
  }

  async refreshPreview(candidate) {
    const token = ++this.previewToken
    const url = new URL(this.urlValue, window.location.origin)
    url.pathname = url.pathname.replace(/merge_candidates$/, "impact_preview")
    const actionName = this.hasActionNameValue ? this.actionNameValue : "move_alias"
    url.searchParams.set("action_name", actionName)
    url.searchParams.set("alias_name", this.element.querySelector('[name="alias_name"]')?.value || "this alias")
    if (actionName === "merge") {
      url.searchParams.set("source_topic_id", this.element.querySelector('[name="source_topic_id"]')?.value || "")
    } else {
      url.searchParams.set("target_topic_id", candidate.topicId)
    }
    const aliasCount = this.element.querySelector('[name="alias_count"]')?.value || "1"
    url.searchParams.set("alias_count", aliasCount)

    const response = await fetch(url.toString(), { headers: { Accept: "text/html" } })
    if (!response.ok) return
    if (token !== this.previewToken) return

    if (this.hasPreviewTarget) this.previewTarget.innerHTML = await response.text()
  }
}
