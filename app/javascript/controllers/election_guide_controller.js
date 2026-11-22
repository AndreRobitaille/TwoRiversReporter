import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["disclosure"]

  connect() {
    this.sidebar = window.matchMedia("(min-width: 58rem)")
    this.applyLayout = () => {
      this.disclosureTarget.open = this.sidebar.matches
      this.openLinkedGuide()
    }
    this.sidebar.addEventListener("change", this.applyLayout)
    this.applyLayout()
  }

  disconnect() {
    this.sidebar.removeEventListener("change", this.applyLayout)
  }

  openLinkedGuide() {
    const anchor = window.location.hash.slice(1)
    if (anchor && this.element.contains(document.getElementById(anchor))) {
      this.disclosureTarget.open = true
    }
  }
}
