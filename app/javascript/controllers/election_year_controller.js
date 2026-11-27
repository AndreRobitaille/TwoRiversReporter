import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.restoreSelection()
  }

  restoreSelection() {
    this.element.reset()
  }

  navigate() {
    this.element.requestSubmit()
  }
}
