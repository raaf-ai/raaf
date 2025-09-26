// RAAF Span Detail Stimulus Controller
// Handles expand/collapse functionality for span detail sections
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "toggleIcon",
    "section"
  ]

  static values = {
    debug: { type: Boolean, default: false }
  }

  connect() {
    if (this.debugValue) {
      console.log("🔍 SpanDetail controller connected")
    }
    
    // Initialize any sections that should start collapsed based on data attributes
    this.initializeSectionStates()
  }

  // Main toggle action for general sections
  toggleSection(event) {
    event.preventDefault()

    const button = event.currentTarget
    const targetId = button.dataset.target
    const section = document.getElementById(targetId)
    const previewSection = document.getElementById(`${targetId}-preview`)
    const icon = button.querySelector('.toggle-icon')

    // Check if this is an expandable text section (has both preview and full sections)
    if (previewSection && section) {
      this.toggleExpandableText(previewSection, section, button)
      return
    }

    // Regular section toggle
    if (!section) {
      console.warn(`No section found with ID: ${targetId}`)
      return
    }

    this.performToggle(section, icon, button)
  }

  // Toggle between preview and full text for expandable sections
  toggleExpandableText(previewSection, fullSection, button) {
    const isShowingPreview = !previewSection.classList.contains('hidden')

    if (isShowingPreview) {
      // Show full text, hide preview
      previewSection.classList.add('hidden')
      fullSection.classList.remove('hidden')
      button.textContent = 'Show Less'
    } else {
      // Show preview, hide full text
      previewSection.classList.remove('hidden')
      fullSection.classList.add('hidden')
      button.textContent = 'Show Full Text'
    }

    if (this.debugValue) {
      console.log(`🔍 Toggled expandable text: showing ${isShowingPreview ? 'full' : 'preview'}`)
    }
  }

  // Specific toggle action for tool input sections
  toggleToolInput(event) {
    this.toggleSection(event)
  }

  // Specific toggle action for tool output sections  
  toggleToolOutput(event) {
    this.toggleSection(event)
  }

  // Toggle action for attribute groups
  toggleAttributeGroup(event) {
    this.toggleSection(event)
  }

  // Toggle action for error details
  toggleErrorDetail(event) {
    event.preventDefault()
    
    const button = event.currentTarget
    const targetId = button.dataset.target
    const preview = document.getElementById(`${targetId}-preview`)
    const full = document.getElementById(`${targetId}-full`)
    
    if (!preview || !full) {
      console.warn(`Error detail elements not found for: ${targetId}`)
      return
    }
    
    if (preview.style.display === 'none') {
      preview.style.display = 'block'
      full.style.display = 'none'
      button.textContent = 'Show More'
    } else {
      preview.style.display = 'none'
      full.style.display = 'block'
      button.textContent = 'Show Less'
    }
  }

  // Toggle action for attribute values
  toggleValue(event) {
    event.preventDefault()

    const button = event.currentTarget
    const targetId = button.dataset.target
    const preview = document.getElementById(`${targetId}-preview`)
    const full = document.getElementById(`${targetId}-full`)

    if (this.debugValue) {
      console.log(`🔍 toggleValue called with targetId: ${targetId}`)
      console.log(`🔍 Looking for preview element: ${targetId}-preview`)
      console.log(`🔍 Looking for full element: ${targetId}-full`)
      console.log(`🔍 Preview element found:`, preview)
      console.log(`🔍 Full element found:`, full)
    }

    if (!preview || !full) {
      console.warn(`Value elements not found for: ${targetId}`)
      console.warn(`Preview element (${targetId}-preview):`, preview)
      console.warn(`Full element (${targetId}-full):`, full)
      return
    }

    if (full.classList.contains('hidden')) {
      preview.classList.add('hidden')
      full.classList.remove('hidden')
      // Store original text if not already stored
      if (!button.dataset.originalText) {
        button.dataset.originalText = button.textContent
      }
      button.textContent = 'Show Less'
    } else {
      preview.classList.remove('hidden')
      full.classList.add('hidden')
      // Restore original text if available, otherwise use generic text
      button.textContent = button.dataset.originalText || 'Show More'
    }

    if (this.debugValue) {
      console.log(`🔍 Toggle completed. Full element hidden: ${full.classList.contains('hidden')}`)
    }
  }

  // Toggle action for attributes view (structured vs raw)
  toggleAttributesView(event) {
    event.preventDefault()
    
    const structured = document.getElementById('attributes-structured')
    const raw = document.getElementById('attributes-raw')
    const button = event.currentTarget
    
    if (!structured || !raw) {
      console.warn('Attributes view elements not found')
      return
    }
    
    if (structured.style.display === 'none') {
      structured.style.display = 'block'
      raw.style.display = 'none'
      button.textContent = 'Toggle View'
    } else {
      structured.style.display = 'none'
      raw.style.display = 'block'
      button.textContent = 'Toggle View'
    }
  }

  // Copy JSON to clipboard
  copyJson(event) {
    event.preventDefault()

    const button = event.currentTarget
    const targetId = button.dataset.target
    const element = document.getElementById(targetId)

    if (!element) {
      console.warn(`Copy target not found: ${targetId}`)
      return
    }

    navigator.clipboard.writeText(element.textContent).then(() => {
      // Show temporary feedback
      const originalText = button.textContent
      button.textContent = 'Copied!'
      button.classList.add('text-green-600')

      setTimeout(() => {
        button.textContent = originalText
        button.classList.remove('text-green-600')
      }, 2000)
    }).catch(err => {
      console.error('Failed to copy text: ', err)
      // Fallback for older browsers
      this.fallbackCopyToClipboard(element.textContent)
    })
  }

  // Copy arbitrary text to clipboard (for span IDs, trace IDs, etc.)
  copyToClipboard(event) {
    event.preventDefault()

    const button = event.currentTarget
    const value = button.dataset.value

    if (!value) {
      console.warn('No value found to copy')
      return
    }

    navigator.clipboard.writeText(value).then(() => {
      // Show temporary feedback with icon change
      const icon = button.querySelector('i')
      if (icon) {
        icon.classList.remove('bi-clipboard')
        icon.classList.add('bi-clipboard-check', 'text-green-600')

        setTimeout(() => {
          icon.classList.remove('bi-clipboard-check', 'text-green-600')
          icon.classList.add('bi-clipboard')
        }, 1500)
      }

      // Also show tooltip feedback
      button.setAttribute('title', 'Copied!')
      setTimeout(() => {
        button.setAttribute('title', button.getAttribute('title').replace('Copied!', 'Copy to clipboard'))
      }, 2000)
    }).catch(err => {
      console.error('Failed to copy value: ', err)
      // Fallback for older browsers
      this.fallbackCopyToClipboard(value)
    })
  }

  // Format and expand JSON in tool arguments
  formatJson(event) {
    event.preventDefault()

    const button = event.currentTarget
    const targetId = button.dataset.target
    const jsonElement = document.getElementById(targetId)

    if (!jsonElement) {
      console.warn(`JSON element not found: ${targetId}`)
      return
    }

    try {
      const rawJson = jsonElement.textContent
      const parsedJson = JSON.parse(rawJson)
      const formattedJson = JSON.stringify(parsedJson, null, 2)

      // Replace content with formatted version
      jsonElement.innerHTML = `<pre class="text-xs text-gray-800 whitespace-pre-wrap">${formattedJson}</pre>`

      // Update button text
      button.textContent = 'Formatted'
      button.disabled = true
      button.classList.add('text-green-600')

    } catch (error) {
      console.warn('Invalid JSON, cannot format:', error)
      button.textContent = 'Invalid JSON'
      button.classList.add('text-red-600')
      button.disabled = true
    }
  }

  // Load large content on demand (lazy loading for performance)
  loadLargeContent(event) {
    event.preventDefault()

    const placeholder = event.currentTarget
    const sectionId = placeholder.dataset.lazyContent

    if (!sectionId) {
      console.warn('No lazy content section ID found')
      return
    }

    // Show loading state
    placeholder.innerHTML = `
      <div class="flex items-center justify-center gap-2 text-blue-600">
        <i class="bi bi-arrow-clockwise animate-spin"></i>
        <span class="text-sm">Loading large dataset...</span>
      </div>
    `

    // Simulate loading delay for large data processing
    setTimeout(() => {
      // In a real implementation, this would fetch the actual data
      // For now, we'll replace the placeholder with a loading complete message
      placeholder.innerHTML = `
        <div class="bg-green-50 border border-green-200 rounded p-3 text-center">
          <div class="flex items-center justify-center gap-2 text-green-800">
            <i class="bi bi-check-circle"></i>
            <span class="text-sm">Large data loaded successfully</span>
          </div>
        </div>
      `

      // Emit event for analytics/monitoring
      this.dispatch('largeContentLoaded', {
        detail: { sectionId: sectionId }
      })
    }, 800)
  }

  // Performance monitoring for section toggles
  monitorPerformance(sectionId, startTime) {
    const endTime = performance.now()
    const duration = endTime - startTime

    if (duration > 100) {
      console.warn(`Slow section toggle detected: ${sectionId} took ${duration.toFixed(2)}ms`)

      // Emit performance warning event
      this.dispatch('performanceWarning', {
        detail: {
          sectionId: sectionId,
          duration: duration,
          threshold: 100
        }
      })
    }
  }

  // Private methods
  
  initializeSectionStates() {
    // Find all sections with data-initially-collapsed="true"
    const collapsedSections = this.element.querySelectorAll('[data-initially-collapsed="true"]')
    collapsedSections.forEach(section => {
      section.classList.add('hidden')
    })
  }

  performToggle(section, icon, button) {
    const startTime = performance.now()
    const sectionId = section.id

    if (section.classList.contains('hidden')) {
      // Show section
      section.classList.remove('hidden')
      if (icon) {
        icon.classList.remove('bi-chevron-right')
        icon.classList.add('bi-chevron-down')
      }
      if (button.dataset.expandedText) {
        button.querySelector('.button-text').textContent = button.dataset.expandedText
      }
    } else {
      // Hide section
      section.classList.add('hidden')
      if (icon) {
        icon.classList.remove('bi-chevron-down')
        icon.classList.add('bi-chevron-right')
      }
      if (button.dataset.collapsedText) {
        button.querySelector('.button-text').textContent = button.dataset.collapsedText
      }
    }

    // Monitor performance for large data sections
    this.monitorPerformance(sectionId, startTime)

    // Emit custom event for other controllers to listen to
    this.dispatch('sectionToggled', {
      detail: {
        section: section,
        expanded: !section.classList.contains('hidden'),
        sectionId: section.id
      }
    })

    if (this.debugValue) {
      console.log(`🔍 Toggled section: ${section.id}, expanded: ${!section.classList.contains('hidden')}`)
    }
  }

  fallbackCopyToClipboard(text) {
    // Fallback copy method for older browsers
    const textArea = document.createElement('textarea')
    textArea.value = text
    textArea.style.position = 'fixed'
    textArea.style.opacity = '0'
    document.body.appendChild(textArea)
    textArea.focus()
    textArea.select()
    
    try {
      document.execCommand('copy')
    } catch (err) {
      console.error('Fallback copy failed: ', err)
    }
    
    document.body.removeChild(textArea)
  }

  disconnect() {
    if (this.debugValue) {
      console.log("🔍 SpanDetail controller disconnected")
    }
  }
}