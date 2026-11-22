import { Controller } from "@hotwired/stimulus"

// Bookmarks can point to a finding or a control inside the council-work disclosure.
export default class extends Controller {
  connect() {
    this.reveal()
  }

  reveal() {
    const target = document.getElementById(window.location.hash.slice(1))
    if (!target || !this.element.contains(target)) return

    let disclosure = target.closest("details")
    if (!disclosure) return

    while (disclosure) {
      disclosure.open = true
      disclosure = disclosure.parentElement.closest("details")
    }
    target.scrollIntoView()
  }
}
