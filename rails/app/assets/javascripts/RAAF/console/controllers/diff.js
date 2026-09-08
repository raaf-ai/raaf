// The replay comparison: what the original run said against what the replay
// said, rendered by diff2html.
class DiffController extends Controller {
  static targets = ["container"]
  static values = {
    original: String,
    replayed: String,
    outputStyle: { type: String, default: "side-by-side" }
  }

  connect() {
    // hljs is in the list because the base diff2html build has no highlighter
    // of its own — highlightCode() throws without the one handed to the
    // constructor. All three come from a CDN, so say so in the container when
    // they never arrive rather than leaving the reader looking at an empty box.
    waitForGlobals(["Diff", "Diff2HtmlUI", "hljs"], { attempts: 200, delay: 50 })
      .then(() => this.renderDiff())
      .catch((error) => {
        console.warn("Diff libraries unavailable:", error)
        if (this.hasContainerTarget) {
          this.containerTarget.textContent =
            "Could not load the diff viewer. Check the network tab for a blocked CDN request."
        }
      })
  }

  renderDiff() {
    const original = this.originalValue || ""
    const replayed = this.replayedValue || ""

    if (!original && !replayed) {
      this.containerTarget.innerHTML =
        '<p class="text-gray-500 italic p-4">No output to compare</p>'
      return
    }

    const unifiedDiff = window.Diff.createTwoFilesPatch(
      "original", "replayed", original, replayed,
      "Original Output", "Replayed Output", { context: 3 }
    )

    const ui = new window.Diff2HtmlUI(this.containerTarget, unifiedDiff, {
      drawFileList: false,
      matching: "lines",
      outputFormat: this.outputStyleValue === "line-by-line" ? "line-by-line" : "side-by-side",
      highlight: true,
      renderNothingWhenEmpty: false
    }, window.hljs)

    ui.draw()
    ui.highlightCode()
  }

  toggleView(event) {
    this.outputStyleValue = event.params.outputStyle || "side-by-side"

    // The toggle is a tab strip from the library, so the active one is marked
    // the way every other tab in the console is.
    const button = event.currentTarget
    button.parentElement.querySelectorAll(".raaf-tab").forEach((tab) => {
      const active = tab === button
      tab.classList.toggle("is-active", active)
      tab.setAttribute("aria-selected", active ? "true" : "false")
    })

    this.renderDiff()
  }
}
