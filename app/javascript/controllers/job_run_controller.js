// app/javascript/controllers/job_run_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "typeRadio", "meetingTargets", "topicTargets",
    "dateFrom", "dateTo", "committeeFilter",
    "countPreview", "allTopics", "topicSelect"
  ]

  selectType(event) {
    const scope = event.params.scope
    const card = event.currentTarget

    // Update visual selection
    this.element.querySelectorAll(".job-type-card").forEach(c => c.classList.remove("selected"))
    card.classList.add("selected")

    // Check the radio
    const radio = card.querySelector("input[type=radio]")
    if (radio) radio.checked = true

    // Show/hide target sections
    this.meetingTargetsTarget.classList.toggle("hidden", scope !== "meeting")
    this.topicTargetsTarget.classList.toggle("hidden", scope !== "topic")
  }

  async updateCount() {
    const jobType = this.element.querySelector("input[name='job_type']:checked")?.value
    const dateFrom = this.dateFromTarget.value
    const dateTo = this.dateToTarget.value

    if (!jobType || !dateFrom || !dateTo) {
      this.countPreviewTarget.textContent = "Select a date range to see matching meetings."
      return
    }

    const params = new URLSearchParams({
      job_type: jobType,
      date_from: dateFrom,
      date_to: dateTo
    })

    const committeeId = this.committeeFilterTarget.value
    if (committeeId) params.append("committee_id", committeeId)

    try {
      const response = await fetch(`/admin/job_runs/count?${params}`, {
        headers: { "Accept": "application/json" }
      })
      const data = await response.json()
      this.countPreviewTarget.textContent = `${data.count} meeting(s) in range.`
    } catch {
      this.countPreviewTarget.textContent = "Unable to fetch count."
    }
  }

  toggleAllTopics() {
    const checked = this.allTopicsTarget.checked
    this.topicSelectTarget.classList.toggle("hidden", checked)
  }
}
