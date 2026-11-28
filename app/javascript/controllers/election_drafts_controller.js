import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const rows = [...this.element.querySelectorAll("[data-source-url]")]
    const prefix = "forum-desk:" + this.element.dataset.user + ":"
    try {
      for (const key of Object.keys(localStorage)) {
        if (!key.startsWith(prefix) || key.endsWith(":position")) continue
        let draft
        try { draft = JSON.parse(localStorage.getItem(key)) } catch { continue }
        if (!draft?.annotations?.length || !draft.sourceSha256) continue
        const row = rows.find(item => item.dataset.sourceUrl === draft.sourceUrl &&
          item.dataset.election === draft.electionOn && key === prefix + [draft.sourceSha256, item.dataset.version].filter(Boolean).join(":"))
        const link = row?.querySelector("[data-label-action]")
        if (!link) continue
        const count = draft.annotations.reduce((sum, label) => sum + label.end - label.start, 0)
        row.querySelector("[data-source-status]").textContent = count.toLocaleString() + " words labeled in this browser"
        link.textContent = "Resume labeling"
      }
    } catch { /* Browsers with storage disabled can still open all sources. */ }
  }
}
