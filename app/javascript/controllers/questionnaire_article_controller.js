import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body", "evidence", "status", "save"]
  static values = { url: String }

  disconnect() {
    this.pending?.abort()
  }

  paste(event) {
    const field = this.bodyTarget
    if (field.selectionEnd - field.selectionStart !== field.value.length) return

    const plain = event.clipboardData?.getData("text/plain") || ""
    const pageSource = /^\s*(?:<!doctype html|<html\b)/i.test(plain)
    const html = pageSource ? plain : event.clipboardData?.getData("text/html")
    if (!html || !/<h[23]\b/i.test(html)) return

    event.preventDefault()
    if (!pageSource) field.value = plain
    this.read(new File([html], "clipboard.html", { type: "text/html" }), !pageSource)
  }

  choose(event) {
    const file = event.target.files[0]
    if (file) this.read(file, false)
    event.target.value = ""
  }

  edit() {
    this.pending?.abort()
    this.saveTarget.disabled = false
    this.statusTarget.textContent = ""
  }

  async read(file, clipboard) {
    this.pending?.abort()
    const request = new AbortController()
    this.pending = request
    this.evidenceTarget.value = ""
    this.saveTarget.disabled = true
    this.statusTarget.textContent = "Reading the Council section…"
    const form = new FormData()
    form.append("article_file", file)
    if (clipboard) form.append("clipboard", "1")
    try {
      const response = await fetch(this.urlValue, {
        method: "POST", body: form, signal: request.signal,
        headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content, Accept: "application/json" }
      })
      const result = await response.json()
      if (!response.ok) throw new Error(result.error)
      this.bodyTarget.value = result.body
      this.evidenceTarget.value = result.portrait_evidence
      const portraits = result.photo_count === 1 ? "1 named portrait" : `${result.photo_count} named portraits`
      this.statusTarget.textContent = `Council answers ready to save · ${portraits}.`
    } catch (error) {
      if (!request.signal.aborted) {
        this.statusTarget.textContent = clipboard ? "Review the pasted text. Portraits could not be read from this selection." : (error.message || "The article could not be read. Paste the Council answers to continue.")
      }
    } finally {
      if (this.pending === request) this.saveTarget.disabled = false
    }
  }
}
