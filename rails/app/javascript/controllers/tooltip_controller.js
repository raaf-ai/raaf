import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Initialize tooltips with multiple retry attempts
    this.initializeWithRetries()

    // Re-initialize tooltips when content changes (for Turbo navigation)
    document.addEventListener('turbo:load', this.initializeWithRetries.bind(this))
    document.addEventListener('turbo:frame-load', this.initializeWithRetries.bind(this))

    // Also listen for window load in case script loads later
    window.addEventListener('load', this.initializeWithRetries.bind(this))
  }

  disconnect() {
    document.removeEventListener('turbo:load', this.initializeWithRetries.bind(this))
    document.removeEventListener('turbo:frame-load', this.initializeWithRetries.bind(this))
    window.removeEventListener('load', this.initializeWithRetries.bind(this))
  }

  initializeWithRetries() {
    let attempts = 0
    const maxAttempts = 10
    const retryDelay = 200

    const tryInitialize = () => {
      attempts++

      if (typeof window.HSTooltip !== 'undefined') {
        try {
          // Initialize all tooltips
          window.HSTooltip.autoInit()
          return true // Success
        } catch (error) {
          return false
        }
      } else {
        if (attempts < maxAttempts) {
          setTimeout(tryInitialize, retryDelay)
        } else {
          // Fallback: Try to load Preline manually
          this.loadPrelineFallback()
        }
        return false
      }
    }

    tryInitialize()
  }

  loadPrelineFallback() {
    // Check if script already exists
    if (document.querySelector('script[src*="preline.js"]')) {
      return
    }

    // Try loading Preline script manually
    const script = document.createElement('script')
    script.src = 'https://preline.co/assets/js/preline.js'
    script.onload = () => {
      setTimeout(() => this.initializeWithRetries(), 100)
    }
    script.onerror = () => {
      // Silently handle fallback loading failure
    }

    document.head.appendChild(script)
  }

  // Method to manually refresh tooltips (can be called from other controllers)
  refreshTooltips() {
    this.initializeWithRetries()
  }
}