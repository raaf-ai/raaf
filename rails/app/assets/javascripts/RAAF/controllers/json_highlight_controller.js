import { Controller } from "@hotwired/stimulus"

// JSON syntax highlighting controller for RAAF tracing interface
// Depends on highlight.js being loaded globally
export default class extends Controller {
  static targets = ["json"]

  connect() {
    this.highlightAll()
  }

  highlightAll() {
    this.jsonTargets.forEach(element => {
      this.highlightElement(element)
    })
  }

  highlightElement(element) {
    if (!window.hljs) {
      // If highlight.js hasn't loaded yet, retry after a short delay
      setTimeout(() => this.highlightElement(element), 100)
      return
    }

    try {
      // Ensure the element has the correct class for JSON highlighting
      element.classList.add('language-json')

      // Apply syntax highlighting
      window.hljs.highlightElement(element)

      // Add custom styling for better JSON readability
      this.addJsonFormatting(element)
    } catch (error) {
      console.warn('Failed to highlight JSON:', error)
    }
  }

  addJsonFormatting(element) {
    // Add line numbers if the content is large
    const lines = element.textContent.split('\n').length
    if (lines > 10) {
      element.classList.add('json-with-lines')
    }

    // Add copy button
    this.addCopyButton(element)
  }

  addCopyButton(element) {
    const wrapper = element.parentElement
    if (!wrapper || wrapper.querySelector('.json-copy-button')) {
      return // Button already exists
    }

    const button = document.createElement('button')
    button.className = 'json-copy-button absolute top-2 right-2 px-2 py-1 text-xs bg-gray-700 text-white rounded hover:bg-gray-600 transition-colors'
    button.textContent = 'Copy'
    button.setAttribute('title', 'Copy JSON to clipboard')

    button.addEventListener('click', (e) => {
      e.preventDefault()
      this.copyToClipboard(element.textContent)
      this.showCopyFeedback(button)
    })

    // Make wrapper relative if it isn't already
    if (window.getComputedStyle(wrapper).position === 'static') {
      wrapper.style.position = 'relative'
    }

    wrapper.appendChild(button)
  }

  copyToClipboard(text) {
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).catch(err => {
        console.warn('Failed to copy to clipboard:', err)
        this.fallbackCopyTextToClipboard(text)
      })
    } else {
      this.fallbackCopyTextToClipboard(text)
    }
  }

  fallbackCopyTextToClipboard(text) {
    const textArea = document.createElement("textarea")
    textArea.value = text
    textArea.style.top = "0"
    textArea.style.left = "0"
    textArea.style.position = "fixed"

    document.body.appendChild(textArea)
    textArea.focus()
    textArea.select()

    try {
      document.execCommand('copy')
    } catch (err) {
      console.warn('Fallback copy failed:', err)
    }

    document.body.removeChild(textArea)
  }

  showCopyFeedback(button) {
    const originalText = button.textContent
    button.textContent = 'Copied!'
    button.classList.add('bg-green-600')
    button.classList.remove('bg-gray-700', 'hover:bg-gray-600')

    setTimeout(() => {
      button.textContent = originalText
      button.classList.remove('bg-green-600')
      button.classList.add('bg-gray-700', 'hover:bg-gray-600')
    }, 2000)
  }

  // Method to highlight new JSON content dynamically added to the page
  highlightNew() {
    this.highlightAll()
  }
}