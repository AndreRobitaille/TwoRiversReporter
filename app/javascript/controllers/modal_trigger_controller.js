import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    topicId: String,
    topicName: String
  }

  open() {
    // Find the modal controller
    const modalElement = document.getElementById("merge-modal")
    if (modalElement) {
      const modalController = this.application.getControllerForElementAndIdentifier(modalElement, "modal")
      if (modalController) {
        modalController.open({
          detail: {
            topicId: this.topicIdValue,
            topicName: this.topicNameValue
          }
        })
      }
    }
  }
}
