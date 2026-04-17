import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card", "panel", "trigger", "chevron"]

  connect() {
    if (this.hasCardTarget && !this.cardTargets.some((card) => card.dataset.expanded === "true")) {
      this.open(this.cardTargets[0])
    }
  }

  toggle(event) {
    const card = event.currentTarget.closest("[data-topic-decision-board-target='card']")
    if (card.dataset.expanded === "true") {
      return
    }

    this.cardTargets.forEach((target) => this.close(target))
    this.open(card)
  }

  open(card) {
    card.dataset.expanded = "true"
    const panel = card.querySelector("[data-topic-decision-board-target='panel']")
    const trigger = card.querySelector("[data-topic-decision-board-target='trigger']")
    const chevron = card.querySelector("[data-topic-decision-board-target='chevron']")
    if (panel) panel.hidden = false
    if (trigger) trigger.setAttribute("aria-expanded", "true")
    if (chevron) chevron.textContent = "Collapse"
  }

  close(card) {
    card.dataset.expanded = "false"
    const panel = card.querySelector("[data-topic-decision-board-target='panel']")
    const trigger = card.querySelector("[data-topic-decision-board-target='trigger']")
    const chevron = card.querySelector("[data-topic-decision-board-target='chevron']")
    if (panel) panel.hidden = true
    if (trigger) trigger.setAttribute("aria-expanded", "false")
    if (chevron) chevron.textContent = "Expand"
  }
}
