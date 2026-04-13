import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "copyButton"]
  static values = { text: String, url: String }

  toggle(event) {
    event.stopPropagation()
    this.dropdownTarget.hidden = !this.dropdownTarget.hidden
  }

  facebook(event) {
    event.preventDefault()
    const shareUrl = `https://www.facebook.com/sharer/sharer.php?u=${encodeURIComponent(this.urlValue)}`
    const width = 600
    const height = 400
    const left = (screen.width - width) / 2
    const top = (screen.height - height) / 2
    window.open(shareUrl, "facebook-share", `width=${width},height=${height},left=${left},top=${top}`)
    this.dropdownTarget.hidden = true
  }

  copy(event) {
    event.preventDefault()
    navigator.clipboard.writeText(this.textValue).then(() => {
      const button = this.copyButtonTarget
      const original = button.textContent
      button.textContent = "Copied!"
      setTimeout(() => { button.textContent = original }, 2000)
    })
    this.dropdownTarget.hidden = true
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
