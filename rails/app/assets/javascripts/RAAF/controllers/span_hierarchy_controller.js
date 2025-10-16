// Stimulus controller for expandable span hierarchy tree view
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["expandButton", "children"]
  static classes = ["expanded", "collapsed"]

  connect() {
    // Initialize all spans as collapsed (children hidden)
    this.initializeCollapsedState()
  }

  initializeCollapsedState() {
    // Find all expand buttons and ensure they start in collapsed state
    const expandButtons = this.element.querySelectorAll('.expand-button')

    expandButtons.forEach(button => {
      // Reset button to collapsed state (text chevron points right)
      button.textContent = '▶'
      // Ensure button starts with proper styling
      button.classList.remove('bg-blue-100')
      button.classList.add('bg-gray-100')
    })

    // Hide all children rows initially
    const childrenRows = this.element.querySelectorAll('tr.span-children')

    childrenRows.forEach(row => {
      row.classList.add('hidden')
    })
  }

  toggleChildren(event) {
    event.preventDefault()
    event.stopPropagation()

    const button = event.currentTarget
    const spanId = button.dataset.spanId

    // Find all children rows for this span
    const childrenRows = this.element.querySelectorAll(
      'tr.span-children[data-parent-span-id="' + spanId + '"]'
    )

    if (childrenRows.length === 0) {
      return
    }

    // Check if children are currently hidden
    const isCurrentlyHidden = childrenRows[0].classList.contains('hidden')

    if (isCurrentlyHidden) {
      // Expand: show children and change chevron to down
      childrenRows.forEach(row => {
        row.classList.remove('hidden')
      })

      // Change chevron from right (▶) to down (▼)
      button.textContent = '▼'

      // Add visual feedback to button
      button.classList.add('bg-blue-100', 'border-blue-400')
      button.classList.remove('bg-gray-100', 'border-gray-300')
      button.classList.add('text-blue-800')

      // Animate the appearance
      childrenRows.forEach((row, index) => {
        requestAnimationFrame(() => {
          row.style.opacity = '0'
          row.style.transform = 'translateY(-10px)'
          row.style.transition = 'opacity 0.2s ease-out ' + (index * 0.05) + 's, transform 0.2s ease-out ' + (index * 0.05) + 's'

          requestAnimationFrame(() => {
            row.style.opacity = '1'
            row.style.transform = 'translateY(0)'
          })
        })
      })

    } else {
      // Collapse: hide children and change chevron to right
      // Change chevron from down (▼) to right (▶)
      button.textContent = '▶'

      // Remove visual feedback from button
      button.classList.remove('bg-blue-100', 'border-blue-400', 'text-blue-800')
      button.classList.add('bg-gray-100', 'border-gray-300')

      // Animate the disappearance
      childrenRows.forEach((row, index) => {
        row.style.transition = 'opacity 0.15s ease-in ' + (index * 0.02) + 's, transform 0.15s ease-in ' + (index * 0.02) + 's'
        row.style.opacity = '0'
        row.style.transform = 'translateY(-5px)'
      })

      setTimeout(() => {
        childrenRows.forEach(row => {
          row.classList.add('hidden')
          row.style.opacity = ''
          row.style.transform = ''
          row.style.transition = ''
        })
      }, 200)

      // Also collapse any expanded grandchildren
      childrenRows.forEach(row => {
        const grandchildrenRows = this.element.querySelectorAll(
          'tr.span-children[data-parent-span-id="' + row.dataset.spanId + '"]'
        )
        grandchildrenRows.forEach(grandchildRow => {
          grandchildRow.classList.add('hidden')
          grandchildRow.style.opacity = ''
          grandchildRow.style.transform = ''
          grandchildRow.style.transition = ''

          // Reset any expanded grandchildren chevrons
          const grandchildButton = grandchildRow.querySelector('.expand-button')
          if (grandchildButton) {
            grandchildButton.textContent = '▶'
            grandchildButton.classList.remove('bg-blue-100', 'border-blue-400', 'text-blue-800')
            grandchildButton.classList.add('bg-gray-100', 'border-gray-300')
          }
        })
      })
    }

    // Track expansion state for potential future features
    this.trackExpansionState(spanId, isCurrentlyHidden)
  }

  expandAll() {
    // Utility method to expand all nodes at once
    const allExpandButtons = this.element.querySelectorAll('.expand-button')
    allExpandButtons.forEach(button => {
      const spanId = button.dataset.spanId
      const childrenRows = this.element.querySelectorAll(
        'tr.span-children[data-parent-span-id="' + spanId + '"]'
      )

      // Only expand if button shows ▶ (collapsed state) and has children
      if (childrenRows.length > 0 && button.textContent === '▶') {
        button.click()
      }
    })
  }

  collapseAll() {
    // Utility method to collapse all nodes at once
    const allExpandButtons = this.element.querySelectorAll('.expand-button')
    allExpandButtons.forEach(button => {
      const spanId = button.dataset.spanId
      const childrenRows = this.element.querySelectorAll(
        'tr.span-children[data-parent-span-id="' + spanId + '"]'
      )

      // Only collapse if button shows ▼ (expanded state) and has children
      if (childrenRows.length > 0 && button.textContent === '▼') {
        button.click()
      }
    })
  }

  trackExpansionState(spanId, wasExpanded) {
    // Optional: Track which spans are expanded for analytics or persistence
    const state = wasExpanded ? 'expanded' : 'collapsed'

    // Could store in localStorage for persistence across page loads
    // or send analytics events here
  }

  // Keyboard navigation support
  keyDown(event) {
    if (event.target.classList.contains('expand-button')) {
      switch (event.key) {
        case 'Enter':
        case ' ':
          event.preventDefault()
          event.target.click()
          break
        case 'ArrowRight':
          // Expand if collapsed (chevron is ▶)
          event.preventDefault()
          if (event.target.textContent === '▶') {
            event.target.click()
          }
          break
        case 'ArrowLeft':
          // Collapse if expanded (chevron is ▼)
          event.preventDefault()
          if (event.target.textContent === '▼') {
            event.target.click()
          }
          break
      }
    }
  }
}