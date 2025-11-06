// RAAF Eval UI JavaScript
// Main application JavaScript entry point

// Import Stimulus controllers
import { Application } from "@hotwired/stimulus"
import MonacoEditorController from "./controllers/monaco_editor_controller"
import EvaluationProgressController from "./controllers/evaluation_progress_controller"
import FormValidationController from "./controllers/form_validation_controller"

// Start Stimulus application
const application = Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus = application

// Register controllers
application.register("monaco-editor", MonacoEditorController)
application.register("evaluation-progress", EvaluationProgressController)
application.register("form-validation", FormValidationController)

// Import Turbo (for Turbo Streams and Frames)
import "@hotwired/turbo-rails"

// Configure Turbo
Turbo.session.drive = true

// Global event handlers
document.addEventListener("turbo:load", () => {
  console.log("RAAF Eval UI loaded")
})

// Handle Turbo form submissions
document.addEventListener("turbo:submit-start", (event) => {
  const form = event.target
  const submitButton = form.querySelector('[type="submit"]')

  if (submitButton) {
    submitButton.disabled = true
    submitButton.classList.add("opacity-50", "cursor-not-allowed")

    // Add loading indicator
    const originalText = submitButton.textContent
    submitButton.textContent = "Loading..."
    submitButton.dataset.originalText = originalText
  }
})

document.addEventListener("turbo:submit-end", (event) => {
  const form = event.target
  const submitButton = form.querySelector('[type="submit"]')

  if (submitButton) {
    submitButton.disabled = false
    submitButton.classList.remove("opacity-50", "cursor-not-allowed")

    // Restore original text
    if (submitButton.dataset.originalText) {
      submitButton.textContent = submitButton.dataset.originalText
      delete submitButton.dataset.originalText
    }
  }
})

// Handle Turbo errors
document.addEventListener("turbo:fetch-request-error", (event) => {
  console.error("Turbo fetch error:", event.detail)
  showNotification("Connection error. Please try again.", "error")
})

// Utility function for notifications
window.showNotification = function(message, type = "info") {
  const colors = {
    success: 'bg-green-600',
    error: 'bg-red-600',
    info: 'bg-blue-600',
    warning: 'bg-yellow-600'
  }

  const notification = document.createElement('div')
  notification.className = `notification-toast ${type} fixed bottom-4 right-4 px-4 py-2 rounded-lg shadow-lg z-50 text-white`
  notification.textContent = message
  document.body.appendChild(notification)

  setTimeout(() => {
    notification.style.opacity = '0'
    notification.style.transition = 'opacity 0.3s'
    setTimeout(() => notification.remove(), 300)
  }, 3000)
}

// Export for use in other modules
export { application, showNotification }
