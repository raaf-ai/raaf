import { Controller } from "@hotwired/stimulus"

// Handles showing/hiding the sample rate config when an evaluator is toggled
// Also handles showing/hiding the "Evaluate every" control based on trigger mode
export default class extends Controller {
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
    const isChecked = this.checkboxTarget.checked

    if (isChecked) {
      this.configTarget.classList.remove("hidden")
      this.element.classList.add("bg-blue-50")
      this.element.classList.remove("hover:bg-gray-50")
    } else {
      this.configTarget.classList.add("hidden")
      this.element.classList.remove("bg-blue-50")
      this.element.classList.add("hover:bg-gray-50")
    }
  }

  updateSamplingVisibility() {
    if (!this.hasTriggerModeTarget || !this.hasSamplingConfigTarget) {
      return
    }

    const triggerMode = this.triggerModeTarget.value

    if (triggerMode === "manual") {
      this.samplingConfigTarget.classList.add("hidden")
    } else {
      this.samplingConfigTarget.classList.remove("hidden")
    }
  }
}
