import { Controller } from "@hotwired/stimulus"

// Off-canvas drawer for the admin sidebar below 900px. CSS owns its visual
// position; this controller mirrors the breakpoint for focus and accessibility
// state so the hidden drawer cannot remain keyboard-reachable.
export default class extends Controller {
  static targets = ["drawer", "toggle", "scrim"]

  connect() {
    this.breakpoint = window.matchMedia("(max-width: 900px)")
    this.handleBreakpointChange = this.handleBreakpointChange.bind(this)
    this.breakpoint.addEventListener("change", this.handleBreakpointChange)
    this.setClosed({ restoreFocus: false })
  }

  disconnect() {
    this.breakpoint.removeEventListener("change", this.handleBreakpointChange)
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    if (!this.breakpoint.matches) return

    this.element.classList.add("adm-shell--drawer-open")
    this.toggleTarget.setAttribute("aria-expanded", "true")
    this.toggleTarget.setAttribute("aria-label", "Close navigation")
    this.setDrawerAvailable(true)
    if (this.hasScrimTarget) this.scrimTarget.removeAttribute("hidden")

    this.drawerTarget.querySelector("a, button, input, select, textarea")?.focus()
  }

  close() {
    this.setClosed({ restoreFocus: true })
  }

  handleBreakpointChange() {
    this.setClosed({ restoreFocus: false })
  }

  setClosed({ restoreFocus }) {
    this.element.classList.remove("adm-shell--drawer-open")
    if (this.hasToggleTarget) {
      this.toggleTarget.setAttribute("aria-expanded", "false")
      this.toggleTarget.setAttribute("aria-label", "Open navigation")
    }
    if (this.hasScrimTarget) this.scrimTarget.setAttribute("hidden", "hidden")

    this.setDrawerAvailable(!this.breakpoint.matches)
    if (restoreFocus && this.hasToggleTarget) this.toggleTarget.focus()
  }

  setDrawerAvailable(available) {
    if (!this.hasDrawerTarget) return

    this.drawerTarget.inert = !available
    this.drawerTarget.toggleAttribute("aria-hidden", !available)
  }

  handleKeydown(event) {
    if (event.key === "Escape" && this.isOpen) this.close()
  }

  get isOpen() {
    return this.element.classList.contains("adm-shell--drawer-open")
  }
}
