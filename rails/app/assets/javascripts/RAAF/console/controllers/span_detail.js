// Span detail — the collapsible sections, the show-more toggles and the copy
// buttons on a single span's page.
//
// Sections are addressed by id through `data-target` rather than through
// Stimulus targets, because a payload section and its preview are rendered as
// a pair of sibling elements named `<id>` and `<id>-preview`.
class SpanDetailController extends Controller {
  static targets = ["toggleIcon", "section"]
  static values = { debug: { type: Boolean, default: false } }

  connect() {
    if (this.debugValue) {
      console.log("🔍 SpanDetail controller connected")
    }
    this.initializeSectionStates()
  }

  toggleSection(event) {
    event.preventDefault()

    const button = event.currentTarget
    const targetId = button.dataset.target
    const section = document.getElementById(targetId)
    const previewSection = document.getElementById(targetId + '-preview')
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

  performToggle(section, icon, button) {
    if (section.classList.contains('hidden')) {
      section.classList.remove('hidden')
      if (icon) {
        icon.classList.remove('bi-chevron-right')
        icon.classList.add('bi-chevron-down')
      }
    } else {
      section.classList.add('hidden')
      if (icon) {
        icon.classList.remove('bi-chevron-down')
        icon.classList.add('bi-chevron-right')
      }
    }
  }

  initializeSectionStates() {
    const collapsedSections = this.element.querySelectorAll('[data-initially-collapsed="true"]')
    collapsedSections.forEach(section => {
      section.classList.add('hidden')
    })
  }

  copyToClipboard(event) {
    event.preventDefault()

    const button = event.currentTarget
    const value = button.dataset.value

    if (!value) {
      console.warn('No value found to copy')
      return
    }

    navigator.clipboard.writeText(value).then(() => {
      const icon = button.querySelector('i')
      if (icon) {
        icon.classList.remove('bi-clipboard')
        icon.classList.add('bi-clipboard-check', 'text-green-600')

        setTimeout(() => {
          icon.classList.remove('bi-clipboard-check', 'text-green-600')
          icon.classList.add('bi-clipboard')
        }, 1500)
      }
    }).catch(err => {
      console.error('Failed to copy value: ', err)
    })
  }

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

  disconnect() {
    if (this.debugValue) {
      console.log("🔍 SpanDetail controller disconnected")
    }
  }
}
