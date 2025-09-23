// RAAF Auto-Refresh Stimulus Controller
// Simple page refresh functionality that respects document visibility
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 30000 }, // 30 seconds default
    enabled: { type: Boolean, default: true }
  }

  connect() {
    console.log("🔄 RAAF Auto-Refresh Controller connected")
    console.log(`Refresh interval: ${this.intervalValue}ms, Enabled: ${this.enabledValue}`)

    this.refreshIntervalId = null

    if (this.enabledValue) {
      this.startAutoRefresh()
    }

    // Listen for visibility changes to pause/resume when tab is not active
    this.visibilityChangeHandler = this.handleVisibilityChange.bind(this)
    document.addEventListener('visibilitychange', this.visibilityChangeHandler)
  }

  disconnect() {
    console.log("🔄 RAAF Auto-Refresh Controller disconnecting")
    this.stopAutoRefresh()
    document.removeEventListener('visibilitychange', this.visibilityChangeHandler)
  }

  startAutoRefresh() {
    if (this.refreshIntervalId) {
      this.stopAutoRefresh()
    }

    console.log(`🔄 Starting auto-refresh with ${this.intervalValue}ms interval`)

    this.refreshIntervalId = setInterval(() => {
      this.performRefresh()
    }, this.intervalValue)
  }

  stopAutoRefresh() {
    if (this.refreshIntervalId) {
      console.log("⏹️ Stopping auto-refresh")
      clearInterval(this.refreshIntervalId)
      this.refreshIntervalId = null
    }
  }

  performRefresh() {
    // Only refresh if the document is visible (tab is active)
    if (document.hidden) {
      console.log("📱 Tab not active, skipping refresh")
      return
    }

    console.log("🔄 Auto-refreshing page...")
    window.location.reload()
  }

  handleVisibilityChange() {
    if (document.hidden) {
      console.log("👁️ Tab hidden, auto-refresh will pause")
    } else {
      console.log("👁️ Tab visible, auto-refresh will resume")
    }
  }

  // Action method to manually trigger refresh
  refresh(event) {
    if (event) {
      event.preventDefault()
    }
    console.log("🔄 Manual refresh triggered")
    this.performRefresh()
  }

  // Action method to toggle auto-refresh
  toggle(event) {
    if (event) {
      event.preventDefault()
    }

    this.enabledValue = !this.enabledValue

    if (this.enabledValue) {
      console.log("▶️ Auto-refresh enabled")
      this.startAutoRefresh()
    } else {
      console.log("⏸️ Auto-refresh disabled")
      this.stopAutoRefresh()
    }
  }

  // Getter for current enabled state (useful for UI updates)
  get isEnabled() {
    return this.enabledValue && this.refreshIntervalId !== null
  }

  // Setter for interval value with restart
  intervalValueChanged() {
    if (this.enabledValue && this.refreshIntervalId) {
      console.log(`🔄 Interval changed to ${this.intervalValue}ms, restarting auto-refresh`)
      this.startAutoRefresh()
    }
  }

  // Setter for enabled value
  enabledValueChanged() {
    if (this.enabledValue) {
      this.startAutoRefresh()
    } else {
      this.stopAutoRefresh()
    }
  }
}