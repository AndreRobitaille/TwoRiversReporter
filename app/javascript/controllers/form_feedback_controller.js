import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submit"]

  connect() {
    this.submitButton = this.element.querySelector('input[type="submit"]')
    if (this.submitButton) {
      this.originalText = this.submitButton.value
    }
  }

  submit(event) {
    if (this.submitButton) {
      this.submitButton.value = "Saving..."
      this.submitButton.disabled = true
    }
  }

  // Called when turbo:submit-end event fires
  end(event) {
    if (this.submitButton) {
      const success = event.detail.success
      
      if (success) {
        this.submitButton.value = "Saved!"
        this.submitButton.classList.remove("btn--primary")
        this.submitButton.classList.add("btn--success")
        
        setTimeout(() => {
          this.submitButton.value = this.originalText
          this.submitButton.classList.remove("btn--success")
          this.submitButton.classList.add("btn--primary")
          this.submitButton.disabled = false
        }, 2000)
      } else {
        this.submitButton.value = this.originalText
        this.submitButton.disabled = false
      }
    }
  }
}
