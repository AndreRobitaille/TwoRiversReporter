import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "source", "sourceName", "summary", "language", "results", "selection", "aliasContextQ", "aliasContextSource"]
  static values = { url: String }

  connect() {
    this.searchToken = 0
    this.previewToken = 0
  }

  async search() {
    const query = this.searchTarget.value.trim()
    this.syncAliasContext(query, this.sourceTarget.value.trim())
    const token = ++this.searchToken

    if (!query) {
      this.resultsTarget.innerHTML = ""
      this.clearSelection()
      await this.renderBlankPreview()
      return
    }

    this.clearSelection()
    await this.renderBlankPreview()

    const response = await fetch(`${this.urlValue.replace(/impact_preview$/, "merge_candidates")}?q=${encodeURIComponent(query)}`, {
      headers: { Accept: "text/html" }
    })

    if (!response.ok || token !== this.searchToken) return

    this.resultsTarget.innerHTML = await response.text()
  }

  async selectCandidate(event) {
    const button = event.currentTarget
    this.sourceTarget.value = button.dataset.topicId
    this.sourceNameTarget.value = button.dataset.topicName
    this.syncAliasContext(this.searchTarget.value.trim(), this.sourceTarget.value.trim())
    this.selectionTarget.textContent = `Selected topic: ${button.dataset.topicName}`
    await this.refresh()
  }

  openMergeConfirm() {
    if (!this.sourceTarget.value.trim()) return

    this.openConfirmModal("merge-modal", {
      topicId: this.sourceTarget.value,
      topicName: this.sourceNameTarget.value || this.selectionTarget.textContent.replace(/^Selected topic:\s*/, "")
    })
  }

  openAliasRemoveConfirm(event) {
    this.openConfirmModal(event.currentTarget.dataset.modalId, {
      topicId: event.currentTarget.dataset.aliasId,
      topicName: event.currentTarget.dataset.aliasName
    })
  }

  openAliasPromoteConfirm(event) {
    this.openConfirmModal(event.currentTarget.dataset.modalId, {
      topicId: event.currentTarget.dataset.aliasId,
      topicName: event.currentTarget.dataset.aliasName
    })
  }

  openRetireConfirm(event) {
    this.openConfirmModal(event.currentTarget.dataset.modalId, {
      topicId: event.currentTarget.dataset.topicId,
      topicName: event.currentTarget.dataset.topicName
    })
  }

  openConfirmModal(modalId, detail) {
    const modalElement = document.getElementById(modalId)
    if (!modalElement) return

    const modalController = this.application.getControllerForElementAndIdentifier(modalElement, "modal")
    if (!modalController) return

    modalController.open({ detail })
  }

  clearSelection() {
    this.sourceTarget.value = ""
    this.sourceNameTarget.value = ""
    this.syncAliasContext(this.searchTarget.value.trim(), "")
    this.selectionTarget.textContent = "Choose a topic from search results."
  }

  async renderBlankPreview() {
    const token = ++this.previewToken
    const response = await fetch(this.urlValue, { headers: { Accept: "text/html" } })

    if (!response.ok || token !== this.previewToken) return

    this.summaryTarget.outerHTML = await response.text()
  }

  async refresh() {
    const sourceTopicId = this.sourceTarget.value.trim()
    const token = ++this.previewToken

    if (!sourceTopicId) {
      this.clearSelection()
    }

    const response = await fetch(`${this.urlValue}?source_topic_id=${encodeURIComponent(sourceTopicId)}`, {
      headers: { Accept: "text/html" }
    })

    if (!response.ok || token !== this.previewToken) return

    this.summaryTarget.outerHTML = await response.text()
  }

  syncAliasContext(query, sourceTopicId) {
    this.aliasContextQTargets.forEach((field) => { field.value = query })
    this.aliasContextSourceTargets.forEach((field) => { field.value = sourceTopicId })
  }
}
