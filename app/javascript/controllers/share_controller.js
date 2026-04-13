import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "copyButton", "toggleButton"]
  static values = { text: String, url: String }

  toggle(event) {
    event.stopPropagation()
    this.dropdownTarget.hidden = !this.dropdownTarget.hidden
  }

  facebook(event) {
    event.preventDefault()
    this.dropdownTarget.hidden = true

    // On mobile, use native share sheet — handles Facebook app properly
    if (navigator.share) {
      navigator.share({ text: this.textValue, url: this.urlValue })
        .catch(() => {}) // user cancelled
      return
    }

    // Desktop fallback: copy + open Facebook sharer
    this.#copyToClipboard(this.textValue)
    window.open(`https://www.facebook.com/sharer/sharer.php?u=${encodeURIComponent(this.urlValue)}`, "_blank")
    this.#flashConfirmation("Copied — paste into your group")
  }

  copy(event) {
    event.preventDefault()
    this.#copyToClipboard(this.textValue)
    this.dropdownTarget.hidden = true
    this.#flashConfirmation("Copied!")
  }

  #flashConfirmation(message) {
    const btn = this.toggleButtonTarget
    const svg = btn.querySelector("svg")
    const originalText = btn.textContent.trim()
    btn.textContent = message
    if (svg) btn.prepend(svg)
    btn.classList.add("meeting-doc-link--copied")
    setTimeout(() => {
      btn.textContent = ` ${originalText}`
      if (svg) btn.prepend(svg)
      btn.classList.remove("meeting-doc-link--copied")
    }, 2000)
  }

  #copyToClipboard(text) {
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text)
      return
    }
    // Fallback for non-HTTPS contexts
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.style.position = "fixed"
    textarea.style.opacity = "0"
    document.body.appendChild(textarea)
    textarea.select()
    document.execCommand("copy")
    document.body.removeChild(textarea)
  }

  close(event) {
    if (!this.element.contains(event.target)) {
      this.dropdownTarget.hidden = true
    }
  }

  closeOnEscape(event) {
    if (event.key === "Escape") {
      this.dropdownTarget.hidden = true
    }
  }
}
