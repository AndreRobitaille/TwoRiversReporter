import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit(event) {
    const button = this.element.querySelector('input[type="submit"]')
    if (button) {
      const originalText = button.value
      button.value = "Saving..."
      button.disabled = true
      
      // Store reference for callback
      this.button = button
      this.originalText = originalText
    }
  }

  // Called when turbo:submit-end event fires
  end(event) {
    const success = event.detail.success
    
    if (this.button) {
      if (success) {
        this.button.value = "Saved!"
        this.button.classList.remove("btn--primary")
        this.button.classList.add("btn--success")
        
        setTimeout(() => {
          this.button.value = this.originalText
          this.button.classList.remove("btn--success")
          this.button.classList.add("btn--primary")
          this.button.disabled = false
        }, 1500)
      } else {
        // A 422 (validation failure) re-renders the same row with the same
        // button, so without a distinct visual state here a rejected save is
        // indistinguishable from a successful one — the row just settles
        // back to normal either way. Mirror the success branch's transient
        // color flip so a save that didn't take is at least visible.
        this.button.value = "Not saved"
        this.button.classList.remove("btn--primary")
        this.button.classList.add("btn--danger")

        setTimeout(() => {
          this.button.value = this.originalText
          this.button.classList.remove("btn--danger")
          this.button.classList.add("btn--primary")
          this.button.disabled = false
        }, 2000)
      }
    }
  }
}
