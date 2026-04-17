import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "sourceName", "sourceTopicId", "form"]

  connect() {
    this.element.hidden = true
  }

  open(event) {
    const { topicId, topicName } = event.detail
    if (this.hasSourceNameTarget) {
      this.sourceNameTarget.textContent = topicName
    }

    if (this.hasSourceTopicIdTarget) {
      this.sourceTopicIdTarget.value = topicId
    }

    this.element.hidden = false

    // Find the search controller within this modal and reset it
    const searchElement = this.element.querySelector('[data-controller~="topic-repair-search"]')
    if (searchElement) {
      const searchController = this.application.getControllerForElementAndIdentifier(searchElement, "topic-repair-search")
      if (searchController) {
        searchController.reset()
      }
    }
  }

  close() {
    this.element.hidden = true

    if (this.hasFormTarget) {
      this.formTarget.reset()
    }
  }

  stop(event) {
    event.stopPropagation()
  }
}
