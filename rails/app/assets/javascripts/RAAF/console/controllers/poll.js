// Watches a replay until the worker running it reaches a terminal state, then
// reloads so the finished result is what the page shows.
//
// Unlike AutoRefreshController this asks a question before reloading, because
// a replay usually takes longer than one interval and a blind reload would
// throw away the page several times over on the way to the answer.
class PollController extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 2000 }
  }

  connect() {
    this.poll()
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
  }

  poll() {
    fetch(this.urlValue, { headers: { "Accept": "application/json" } })
      .then((response) => response.json())
      .then((data) => {
        if (data.status === "completed" || data.status === "failed") {
          window.location.reload()
        } else {
          this.again()
        }
      })
      .catch((error) => {
        // A dropped request is not an answer. Keep asking: the run is still
        // going, and the next tick is two seconds away.
        console.warn("Poll error:", error)
        this.again()
      })
  }

  again() {
    this.timer = setTimeout(() => this.poll(), this.intervalValue)
  }
}
