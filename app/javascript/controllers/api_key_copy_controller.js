import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["key", "status"]

  async copy() {
    try {
      await navigator.clipboard.writeText(this.keyTarget.value)
      this.statusTarget.textContent = "Copied. Save the key in your tool’s secret settings."
    } catch {
      this.keyTarget.focus()
      this.keyTarget.select()
      this.statusTarget.textContent = "Select and copy the key above using your device’s copy command."
    }
  }
}
