// Policy form: a check's own configuration follows the box that enables it,
// and the sampling control only applies when something other than a human
// triggers the run.
class EvaluatorToggleController extends Controller {
  static targets = ["checkbox", "config", "triggerMode", "samplingConfig"]

  connect() {
    this.updateVisibility()
    this.updateSamplingVisibility()
  }

  toggle() {
    this.updateVisibility()
  }

  triggerModeChanged() {
    this.updateSamplingVisibility()
  }

  updateVisibility() {
    const on = this.checkboxTarget.checked

    this.configTarget.classList.toggle("hidden", !on)
    this.element.classList.toggle("bg-blue-50", on)
    this.element.classList.toggle("hover:bg-gray-50", !on)
  }

  updateSamplingVisibility() {
    if (!this.hasTriggerModeTarget || !this.hasSamplingConfigTarget) return

    this.samplingConfigTarget.classList.toggle(
      "hidden", this.triggerModeTarget.value === "manual"
    )
  }
}
