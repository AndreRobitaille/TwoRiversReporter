import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "sourceName", "form"]

  connect() {
    this.element.hidden = true
  }

  open(event) {
    const { topicId, topicName } = event.detail
    this.sourceNameTarget.innerText = topicName
    this.formTarget.action = `/admin/topics/${topicId}/merge`
    this.element.hidden = false
    
    // Find the search controller within this modal and reset it
    const searchElement = this.element.querySelector('[data-controller="topic-search"]')
    if (searchElement) {
      const searchController = this.application.getControllerForElementAndIdentifier(searchElement, "topic-search")
      if (searchController) {
        searchController.reset()
      }
    }
  }

  close() {
    this.element.hidden = true
  }

  stop(event) {
    event.stopPropagation()
  }
}
