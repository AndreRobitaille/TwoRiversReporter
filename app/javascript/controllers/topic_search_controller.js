import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results", "targetId", "targetName", "submit", "selection"]

  connect() {
    this.reset()
  }

  reset() {
    this.inputTarget.value = ""
    this.resultsTarget.innerHTML = ""
    this.targetIdTarget.value = ""
    this.targetNameTarget.innerText = ""
    this.selectionTarget.style.display = "none"
    this.inputTarget.style.display = "block"
    this.submitTarget.disabled = true
  }

  search() {
    const query = this.inputTarget.value
    if (query.length < 2) {
      this.resultsTarget.innerHTML = ""
      return
    }

    fetch(`/admin/topics/search?q=${encodeURIComponent(query)}`)
      .then(response => response.json())
      .then(data => {
        if (data.length === 0) {
          this.resultsTarget.innerHTML = `<div class="p-2 text-secondary text-sm">No topics found.</div>`
        } else {
          this.resultsTarget.innerHTML = data.map(topic => `
            <button type="button"
                    class="modal__result"
                    data-action="click->topic-search#select"
                    data-id="${topic.id}"
                    data-name="${topic.name}">
              ${topic.name}
            </button>
          `).join("")
        }
      })
  }

  select(event) {
    const { id, name } = event.currentTarget.dataset
    this.targetIdTarget.value = id
    this.targetNameTarget.innerText = name
    this.resultsTarget.innerHTML = ""
    
    this.inputTarget.style.display = "none"
    this.selectionTarget.style.display = "flex"
    
    this.submitTarget.disabled = false
  }

  clear() {
    this.reset()
    this.inputTarget.focus()
  }
}
