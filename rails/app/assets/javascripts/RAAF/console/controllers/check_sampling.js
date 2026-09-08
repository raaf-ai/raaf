// Per-check sampling: which set of fields the chosen mode needs.
class CheckSamplingController extends Controller {
  static targets = ["modeSelect", "percentageFields", "everyNFields"]

  connect() {
    this.updateVisibility()
  }

  toggle() {
    this.updateVisibility()
  }

  updateVisibility() {
    if (!this.hasModeSelectTarget) return

    const everyN = this.modeSelectTarget.value === "every_n"

    if (this.hasPercentageFieldsTarget) {
      this.percentageFieldsTarget.classList.toggle("hidden", everyN)
    }
    if (this.hasEveryNFieldsTarget) {
      this.everyNFieldsTarget.classList.toggle("hidden", !everyN)
    }
  }
}
