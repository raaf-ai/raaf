// RAAF Auto-Refresh Stimulus Controller
// Simple page refresh functionality that respects document visibility
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 30000 }, // 30 seconds default
    enabled: { type: Boolean, default: true }
  }

  connect() {
    this.refreshIntervalId = null

    if (this.enabledValue) {
      this.startAutoRefresh()
    }

    // Listen for visibility changes to pause/resume when tab is not active
    this.visibilityChangeHandler = this.handleVisibilityChange.bind(this)
    document.addEventListener('visibilitychange', this.visibilityChangeHandler)
  }

  disconnect() {
    this.stopAutoRefresh()
    document.removeEventListener('visibilitychange', this.visibilityChangeHandler)
  }

  startAutoRefresh() {
    if (this.refreshIntervalId) {
      this.stopAutoRefresh()
    }

    this.refreshIntervalId = setInterval(() => {
      this.performRefresh()
    }, this.intervalValue)
  }

  stopAutoRefresh() {
    if (this.refreshIntervalId) {
      clearInterval(this.refreshIntervalId)
      this.refreshIntervalId = null
    }
  }

  performRefresh() {
    // Only refresh if the document is visible (tab is active)
    if (document.hidden) {
      return
    }

    window.location.reload()
  }

  handleVisibilityChange() {
    // Auto-refresh behavior adjusts based on tab visibility
  }

  // Action method to manually trigger refresh
  refresh(event) {
    if (event) {
      event.preventDefault()
    }
    this.performRefresh()
  }

  // Action method to toggle auto-refresh
  toggle(event) {
    if (event) {
      event.preventDefault()
    }

    this.enabledValue = !this.enabledValue

    if (this.enabledValue) {
      this.startAutoRefresh()
    } else {
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