// Experiment editor — the diff rail, the weights total and the
// trigger, from the isEdit screen in RAAF Eval.dc.html.
//
// Every editable control carries the label and the value it was
// loaded with, so the diff compares each field against its own
// `data-diff-initial` rather than against a second copy of the
// record kept in the page.
class ExperimentEditController extends Controller {
  static targets = [
    "field", "changes", "changesEmpty", "dirtyBadge",
    "temperatureValue", "weightTotal", "scorerRow", "cron"
  ]
  static values = { fullWeight: Number }

  connect() {
    this.render()
    this.element.addEventListener("input", () => this.render())
    this.element.addEventListener("change", () => this.render())
  }

  revert() {
    this.fieldTargets.forEach((field) => this.reset(field))
    this.render()
  }

  temperatureChanged() { this.render() }

  triggerChanged() { this.render() }

  // A scorer switched off keeps its numbers — they are what it
  // will use again — and only loses the row's emphasis.
  scorerToggled(event) {
    const row = event.target.closest("[data-experiment-edit-target='scorerRow']")
    if (row) row.classList.toggle("is-off", !event.target.checked)
  }

  render() {
    this.renderTemperature()
    this.renderWeightTotal()
    this.renderCronState()
    this.renderChanges()
  }

  renderTemperature() {
    if (!this.hasTemperatureValueTarget) return
    const slider = this.element.querySelector("input[type='range']")
    if (slider) this.temperatureValueTarget.textContent = Number(slider.value).toFixed(2)
  }

  // Only enabled scorers count, so switching one off cannot make
  // a valid set look wrong.
  renderWeightTotal() {
    if (!this.hasWeightTotalTarget) return

    let total = 0
    this.scorerRowTargets.forEach((row) => {
      const on = row.querySelector("input[type='checkbox']")
      const weight = row.querySelector("input[name$='[weight]']")
      if (on && on.checked && weight) total += Number(weight.value || 0)
    })

    this.weightTotalTarget.textContent = `weights total ${total.toFixed(2)}`
    const full = this.hasFullWeightValue ? this.fullWeightValue : 1
    this.weightTotalTarget.classList.toggle(
      "raaf-weight-total--off", Math.abs(total - full) > 0.001
    )
  }

  renderCronState() {
    if (!this.hasCronTarget) return
    const trigger = this.element.querySelector(
      "input[name$='[trigger]']:checked"
    )
    this.cronTarget.disabled = !trigger || trigger.value !== "cron"
  }

  renderChanges() {
    if (!this.hasChangesTarget) return

    const changes = this.fieldTargets
      .map((field) => this.change(field))
      .filter((change) => change !== null)

    this.changesTarget.replaceChildren(
      ...changes.map((change) => this.row(change))
    )

    if (this.hasChangesEmptyTarget) {
      this.changesEmptyTarget.hidden = changes.length > 0
    }
    if (this.hasDirtyBadgeTarget) {
      this.dirtyBadgeTarget.textContent =
        changes.length === 0
          ? "Saved"
          : `${changes.length} change${changes.length === 1 ? "" : "s"}`
    }
  }

  change(field) {
    const from = field.dataset.diffInitial ?? ""
    const to = this.currentValue(field)
    // An unselected radio has nothing to compare; only the
    // checked one in a group speaks for the group.
    if (to === null || from === to) return null
    return { label: field.dataset.diffLabel || field.name, from, to }
  }

  currentValue(field) {
    if (field.type === "checkbox") return field.checked ? "on" : "off"
    if (field.type === "radio") return field.checked ? this.pillLabel(field) : null
    if (field.tagName === "SELECT") {
      return field.selectedOptions[0] ? field.selectedOptions[0].textContent.trim() : ""
    }
    return field.value
  }

  // A trigger reads as its pill, not as its stored value — the
  // diff should say what the screen says.
  pillLabel(radio) {
    const label = this.element.querySelector(`label[for='${radio.id}']`)
    return label ? label.textContent.trim() : radio.value
  }

  reset(field) {
    const initial = field.dataset.diffInitial ?? ""
    if (field.type === "checkbox") {
      field.checked = initial === "on"
      field.dispatchEvent(new Event("change", { bubbles: true }))
    } else if (field.type === "radio") {
      field.checked = this.pillLabel(field) === initial
    } else if (field.tagName === "SELECT") {
      // A select is tracked by its option's text, because that is
      // what the diff shows — assigning that text as the value
      // would clear the selection instead of restoring it.
      const options = [...field.options]
      const option =
        options.find((o) => o.textContent.trim() === initial) ||
        options.find((o) => o.value === "")
      if (option) field.selectedIndex = option.index
    } else {
      field.value = initial
    }
  }

  row(change) {
    const row = document.createElement("div")
    row.className = "raaf-diff-row"

    const label = document.createElement("span")
    label.className = "raaf-diff-label"
    label.textContent = change.label

    const values = document.createElement("div")
    values.className = "raaf-diff-values"

    const from = document.createElement("span")
    from.className = "raaf-diff-from"
    from.textContent = change.from === "" ? "empty" : change.from

    const arrow = document.createElement("i")
    arrow.className = "bi bi-arrow-right-short raaf-diff-arrow"

    const to = document.createElement("span")
    to.className = "raaf-diff-to"
    to.textContent = change.to === "" ? "empty" : change.to

    values.append(from, arrow, to)
    row.append(label, values)
    return row
  }
}
