// Syntax highlighting for the payloads a span carries.
//
// highlight.js only loads on pages that asked for the syntax bundle, and a CDN
// can fail anywhere, so this waits for it once per element group rather than
// per element and leaves the payload as plain text when it never arrives.
class JsonHighlightController extends Controller {
  static targets = ["json"]

  connect() {
    waitForGlobals(["hljs"], { attempts: 20, delay: 100 })
      .then(() => this.jsonTargets.forEach((element) => this.highlight(element)))
      .catch(() => {
        // Unhighlighted JSON is still readable JSON.
      })
  }

  highlight(element) {
    // highlight.js marks what it has processed; running it twice on the same
    // element corrupts the markup it produced the first time.
    if (element.classList.contains("hljs")) return

    try {
      element.classList.add("language-json")
      window.hljs.highlightElement(element)
    } catch (error) {
      console.warn("Failed to highlight JSON:", error)
    }
  }
}
