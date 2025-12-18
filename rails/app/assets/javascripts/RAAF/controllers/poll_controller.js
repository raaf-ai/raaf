// RAAF Poll Stimulus Controller
// Handles automatic polling for status updates during replay execution
import { Controller } from "@hotwired/stimulus"

// Try to get Turbo from global scope (set by host Rails app)
let Turbo = null
try {
  if (typeof window !== 'undefined' && window.Turbo) {
    Turbo = window.Turbo
  }
} catch (e) {
  // Will use global Turbo if available
}

// Helper to get Turbo instance
const getTurbo = () => {
  if (Turbo) return Turbo
  if (typeof window !== 'undefined' && window.Turbo) return window.Turbo
  return null
}

export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 2000 },
    maxAttempts: { type: Number, default: 60 },
    stopOnComplete: { type: Boolean, default: true },
    debug: { type: Boolean, default: false }
  }

  connect() {
    this.attempts = 0
    this.polling = false

    if (this.hasUrlValue) {
      this.startPolling()
    }

    if (this.debugValue) {
      console.log("Poll controller connected", {
        url: this.urlValue,
        interval: this.intervalValue
      })
    }
  }

  startPolling() {
    if (this.polling) return

    this.polling = true
    this.poll()
  }

  stopPolling() {
    this.polling = false

    if (this.pollTimer) {
      clearTimeout(this.pollTimer)
      this.pollTimer = null
    }

    if (this.debugValue) {
      console.log("Polling stopped", { attempts: this.attempts })
    }
  }

  async poll() {
    if (!this.polling) return

    this.attempts++

    if (this.attempts > this.maxAttemptsValue) {
      this.stopPolling()
      this.handleTimeout()
      return
    }

    try {
      const response = await fetch(this.urlValue, {
        headers: {
          "Accept": "text/vnd.turbo-stream.html, text/html",
          "X-Requested-With": "XMLHttpRequest"
        }
      })

      if (response.ok) {
        const contentType = response.headers.get("content-type")

        if (contentType && contentType.includes("text/vnd.turbo-stream.html")) {
          // Handle Turbo Stream response
          const html = await response.text()
          const turbo = getTurbo()
          if (turbo && turbo.renderStreamMessage) {
            turbo.renderStreamMessage(html)
          } else {
            // Fallback if Turbo not available
            console.warn("Turbo not available, falling back to element replacement")
            this.element.innerHTML = html
          }

          // Check if we should stop polling
          if (this.stopOnCompleteValue && this.isComplete(html)) {
            this.stopPolling()
            return
          }
        } else {
          // Handle regular HTML response - check status in response
          const html = await response.text()

          // Look for completion indicators in the HTML
          if (this.stopOnCompleteValue && this.isComplete(html)) {
            // Replace content and stop polling
            this.element.outerHTML = html
            this.stopPolling()
            return
          }
        }
      } else if (response.status === 404) {
        // Resource not found, stop polling
        this.stopPolling()
        this.handleNotFound()
        return
      }
    } catch (error) {
      if (this.debugValue) {
        console.error("Poll error:", error)
      }
    }

    // Schedule next poll
    this.pollTimer = setTimeout(() => this.poll(), this.intervalValue)
  }

  // Check if the response indicates completion
  isComplete(html) {
    // Look for completion status in the HTML
    const completionIndicators = [
      'status-completed',
      'status="completed"',
      'data-status="completed"',
      'bg-green-50',  // Completed status styling
      'bg-red-50'     // Failed status styling (also means done)
    ]

    return completionIndicators.some(indicator => html.includes(indicator))
  }

  handleTimeout() {
    if (this.debugValue) {
      console.log("Polling timed out")
    }

    // Update UI to show timeout state
    const statusDiv = this.element.querySelector("#replay-status") || this.element

    if (statusDiv) {
      statusDiv.innerHTML = `
        <div class="bg-yellow-50 border border-yellow-200 rounded-xl p-4">
          <div class="flex items-center">
            <i class="bi bi-exclamation-triangle text-yellow-600 text-xl mr-3"></i>
            <div>
              <span class="font-medium text-yellow-800">Timeout</span>
              <span class="ml-2 text-sm text-yellow-600">
                The replay is taking longer than expected. Please refresh the page to check status.
              </span>
            </div>
          </div>
          <div class="mt-3">
            <button type="button"
                    onclick="window.location.reload()"
                    class="inline-flex items-center px-3 py-1.5 border border-yellow-300 rounded-lg text-sm font-medium text-yellow-700 bg-white hover:bg-yellow-50">
              <i class="bi bi-arrow-clockwise mr-1"></i>
              Refresh Page
            </button>
          </div>
        </div>
      `
    }
  }

  handleNotFound() {
    if (this.debugValue) {
      console.log("Resource not found")
    }

    const statusDiv = this.element.querySelector("#replay-status") || this.element

    if (statusDiv) {
      statusDiv.innerHTML = `
        <div class="bg-red-50 border border-red-200 rounded-xl p-4">
          <div class="flex items-center">
            <i class="bi bi-x-circle text-red-600 text-xl mr-3"></i>
            <div>
              <span class="font-medium text-red-800">Not Found</span>
              <span class="ml-2 text-sm text-red-600">
                The replay could not be found. It may have been deleted.
              </span>
            </div>
          </div>
        </div>
      `
    }
  }

  // Manual refresh
  refresh(event) {
    if (event) event.preventDefault()
    this.poll()
  }

  // Pause polling
  pause(event) {
    if (event) event.preventDefault()
    this.stopPolling()
  }

  // Resume polling
  resume(event) {
    if (event) event.preventDefault()
    if (!this.polling) {
      this.attempts = 0
      this.startPolling()
    }
  }

  disconnect() {
    this.stopPolling()

    if (this.debugValue) {
      console.log("Poll controller disconnected")
    }
  }
}
