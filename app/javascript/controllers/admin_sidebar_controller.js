import { Controller } from "@hotwired/stimulus"

// Off-canvas drawer for the admin sidebar below 900px. Above that breakpoint
// the sidebar is always visible and these methods are inert — CSS decides,
// not JS, so there is no resize listener to keep in sync.
export default class extends Controller {
  static targets = ["drawer", "toggle", "scrim"]
  static classes = ["open"]

  connect() {
    this.close()
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this.element.classList.add("adm-shell--drawer-open")
    this.toggleTarget.setAttribute("aria-expanded", "true")
    if (this.hasScrimTarget) this.scrimTarget.removeAttribute("hidden")
  }

  close() {
    this.element.classList.remove("adm-shell--drawer-open")
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", "false")
    if (this.hasScrimTarget) this.scrimTarget.setAttribute("hidden", "hidden")
  }

  // Escape closes the drawer. Bound on the controller element via keydown in
  // the template is unnecessary — document-level is what users expect.
  handleKeydown(event) {
    if (event.key === "Escape") this.close()
  }

  get isOpen() {
    return this.element.classList.contains("adm-shell--drawer-open")
  }
}
