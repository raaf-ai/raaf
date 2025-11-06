// Form Validation Stimulus Controller
// Validates form inputs with real-time feedback

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "error", "submit"]

  connect() {
    this.validateAll()
  }

  validate(event) {
    const input = event.target
    this.validateInput(input)
    this.updateSubmitButton()
  }

  validateInput(input) {
    const errors = []

    // Required validation
    if (input.hasAttribute('required') && !input.value.trim()) {
      errors.push('This field is required')
    }

    // Min/max validation for numbers
    if (input.type === 'number') {
      const value = parseFloat(input.value)
      const min = parseFloat(input.min)
      const max = parseFloat(input.max)

      if (!isNaN(min) && value < min) {
        errors.push(`Value must be at least ${min}`)
      }
      if (!isNaN(max) && value > max) {
        errors.push(`Value must be at most ${max}`)
      }
    }

    // Range validation for sliders
    if (input.type === 'range') {
      const value = parseFloat(input.value)
      const min = parseFloat(input.min)
      const max = parseFloat(input.max)

      if (value < min || value > max) {
        errors.push(`Value must be between ${min} and ${max}`)
      }
    }

    // Custom validation for specific fields
    if (input.name.includes('temperature')) {
      const value = parseFloat(input.value)
      if (value < 0 || value > 2) {
        errors.push('Temperature must be between 0 and 2')
      }
    }

    if (input.name.includes('max_tokens')) {
      const value = parseInt(input.value)
      if (value < 1) {
        errors.push('Max tokens must be at least 1')
      }
      if (value > 100000) {
        errors.push('Max tokens cannot exceed 100,000')
      }
    }

    // Display errors
    this.displayErrors(input, errors)

    return errors.length === 0
  }

  validateAll() {
    let allValid = true

    this.inputTargets.forEach(input => {
      if (!this.validateInput(input)) {
        allValid = false
      }
    })

    this.updateSubmitButton()
    return allValid
  }

  displayErrors(input, errors) {
    // Find or create error container
    let errorContainer = input.nextElementSibling
    if (!errorContainer || !errorContainer.classList.contains('error-message')) {
      errorContainer = document.createElement('div')
      errorContainer.className = 'error-message text-xs text-red-600 mt-1'
      input.parentNode.insertBefore(errorContainer, input.nextSibling)
    }

    if (errors.length > 0) {
      // Show errors
      errorContainer.textContent = errors.join(', ')
      errorContainer.style.display = 'block'
      input.classList.add('border-red-500')
      input.classList.remove('border-gray-300')
    } else {
      // Clear errors
      errorContainer.textContent = ''
      errorContainer.style.display = 'none'
      input.classList.remove('border-red-500')
      input.classList.add('border-gray-300')
    }
  }

  updateSubmitButton() {
    if (!this.hasSubmitTarget) return

    const allValid = this.inputTargets.every(input => {
      const errors = this.validateInput(input)
      return errors
    })

    this.submitTarget.disabled = !this.validateAll()

    if (this.submitTarget.disabled) {
      this.submitTarget.classList.add('opacity-50', 'cursor-not-allowed')
    } else {
      this.submitTarget.classList.remove('opacity-50', 'cursor-not-allowed')
    }
  }

  clearErrors() {
    this.inputTargets.forEach(input => {
      this.displayErrors(input, [])
    })
  }

  // Called before form submission
  validateForm(event) {
    if (!this.validateAll()) {
      event.preventDefault()
      event.stopPropagation()

      // Show notification
      this.showNotification('Please fix validation errors before submitting', 'error')

      // Scroll to first error
      const firstError = this.element.querySelector('.border-red-500')
      if (firstError) {
        firstError.scrollIntoView({ behavior: 'smooth', block: 'center' })
        firstError.focus()
      }

      return false
    }

    return true
  }

  showNotification(message, type) {
    const colors = {
      success: 'bg-green-600',
      error: 'bg-red-600',
      info: 'bg-blue-600'
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
