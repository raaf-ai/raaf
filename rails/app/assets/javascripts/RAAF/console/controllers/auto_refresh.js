// Reloads the page on an interval.
//
// Serves both the shell's Live / Paused control and the sections that are
// waiting on a worker to finish something. Those used to be two controllers,
// `auto-refresh` and `section-refresh`, differing only in that one carried a
// label and the other checked `document.hidden` at tick time instead of
// standing the timer down. A section opts in by declaring an interval and no
// indicator, which is what "section-refresh" meant.
//
// A reload keeps the scroll position and the fragment, so the page comes back
// where it was rather than at the top. A section decides when to stop by no
// longer rendering this controller.
class AutoRefreshController extends Controller {
  static values = { interval: Number, enabled: { type: Boolean, default: true } }
  static targets = ["indicator"]

  connect() {
    this.boundVisibility = () => this.restart()
    document.addEventListener("visibilitychange", this.boundVisibility)
    this.restart()
  }

  disconnect() {
    this.stop()
    document.removeEventListener("visibilitychange", this.boundVisibility)
  }

  toggle(event) {
    if (event) event.preventDefault()
    this.enabledValue = !this.enabledValue
    this.restart()
  }

  restart() {
    this.stop()
    // Don't burn requests refreshing a tab nobody is looking at.
    if (!this.enabledValue || document.hidden || !this.intervalValue) return
    this.timer = setInterval(() => window.location.reload(), this.intervalValue)
    this.render()
  }

  stop() {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
    this.render()
  }

  // Keeps the label and the class the shell served — the design calls this
  // control Live / Paused. A section that renders no indicator gets an empty
  // target list and nothing happens.
  render() {
    this.indicatorTargets.forEach((el) => {
      el.textContent = this.enabledValue ? "Live" : "Paused"
      el.classList.toggle("is-live", this.enabledValue)
    })
  }
}
