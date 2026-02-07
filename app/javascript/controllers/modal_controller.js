import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "sourceName", "form"]

  connect() {
    this.element.classList.add("hidden")
  }

  open(event) {
    const { topicId, topicName } = event.detail
    this.sourceNameTarget.innerText = topicName
    this.formTarget.action = `/admin/topics/${topicId}/merge`
    this.element.classList.remove("hidden")
    
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
    this.element.classList.add("hidden")
  }

  stop(event) {
    event.stopPropagation()
  }
}
