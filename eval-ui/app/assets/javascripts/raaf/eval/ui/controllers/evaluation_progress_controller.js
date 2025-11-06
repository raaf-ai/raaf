// Evaluation Progress Stimulus Controller
// Polls evaluation status and updates progress UI via Turbo Streams

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 1000 }
  }

  connect() {
    this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    if (this.pollInterval) return

    this.pollInterval = setInterval(() => {
      this.fetchStatus()
    }, this.intervalValue)
  }

  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval)
      this.pollInterval = null
    }
  }

  async fetchStatus() {
    try {
      const response = await fetch(this.urlValue, {
        headers: {
          "Accept": "text/vnd.turbo-stream.html",
          "X-Requested-With": "XMLHttpRequest"
        }
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const html = await response.text()
      Turbo.renderStreamMessage(html)

      // Check if evaluation is complete
      const statusElement = document.querySelector('[data-status]')
      if (statusElement) {
        const status = statusElement.dataset.status
        if (status === 'completed' || status === 'failed' || status === 'cancelled') {
          this.stopPolling()
          this.handleCompletion(status)
        }
      }
    } catch (error) {
      console.error('Error fetching status:', error)
      this.handleError(error)
    }
  }

  handleCompletion(status) {
    // Emit custom event that other controllers can listen to
    const event = new CustomEvent('evaluation:completed', {
      detail: { status },
      bubbles: true
    })
    this.element.dispatchEvent(event)

    // Show completion notification
    if (status === 'completed') {
      this.showNotification('Evaluation completed successfully!', 'success')
    } else if (status === 'failed') {
      this.showNotification('Evaluation failed. Check the error details.', 'error')
    }
  }

  handleError(error) {
    console.error('Polling error:', error)
    this.stopPolling()
    this.showNotification('Connection error. Please refresh the page.', 'error')
  }

  cancel(event) {
    event.preventDefault()

    if (!confirm('Are you sure you want to cancel this evaluation?')) {
      return
    }

    this.stopPolling()

    fetch(this.urlValue.replace('/status', '/cancel'), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCsrfToken()
      }
    })
      .then(response => {
        if (response.ok) {
          this.showNotification('Evaluation cancelled', 'info')
          window.location.href = '/eval/sessions'
        }
      })
      .catch(error => {
        console.error('Cancel error:', error)
        this.showNotification('Failed to cancel evaluation', 'error')
      })
  }

  retry(event) {
    event.preventDefault()

    if (!confirm('Retry this evaluation?')) {
      return
    }

    fetch(this.urlValue.replace('/status', '/execute'), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCsrfToken()
      }
    })
      .then(response => {
        if (response.ok) {
          this.showNotification('Evaluation restarted', 'success')
          this.startPolling()
        }
      })
      .catch(error => {
        console.error('Retry error:', error)
        this.showNotification('Failed to retry evaluation', 'error')
      })
  }

  getCsrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ''
  }

  showNotification(message, type) {
    const colors = {
      success: 'bg-green-600',
      error: 'bg-red-600',
      info: 'bg-blue-600',
      warning: 'bg-yellow-600'
    }

    const notification = document.createElement('div')
    notification.className = `fixed bottom-4 right-4 ${colors[type] || colors.info} text-white px-4 py-2 rounded-lg shadow-lg z-50`
    notification.textContent = message
    document.body.appendChild(notification)

    setTimeout(() => {
      notification.remove()
    }, 3000)
  }
}
