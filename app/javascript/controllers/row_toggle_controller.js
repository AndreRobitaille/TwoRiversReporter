import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["details", "button"]

  toggle() {
    const isHidden = this.detailsTarget.hasAttribute("hidden")

    if (isHidden) {
      this.detailsTarget.removeAttribute("hidden")
    } else {
      this.detailsTarget.setAttribute("hidden", "hidden")
    }

    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", isHidden)
      this.buttonTarget.textContent = isHidden ? "Hide Preview" : "Preview"
    }
  }
}
