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
      const chevron = button.querySelector('svg')
      if (chevron) {
        chevron.classList.remove('rotate-90')
      }
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
    const chevron = button.querySelector('svg')

    // Find all children rows for this span
    const childrenRows = this.element.querySelectorAll(
      `tr.span-children[data-parent-span-id="${spanId}"]`
    )

    if (childrenRows.length === 0) {
      console.warn(`No children rows found for span ${spanId}`)
      return
    }

    // Check if children are currently hidden
    const isCurrentlyHidden = childrenRows[0].classList.contains('hidden')

    if (isCurrentlyHidden) {
      // Expand: show children and rotate chevron
      childrenRows.forEach(row => {
        row.classList.remove('hidden')
      })

      if (chevron) {
        chevron.classList.add('rotate-90')
      }

      // Add visual feedback to button
      button.classList.add('bg-blue-100')
      button.classList.remove('bg-gray-100')

      // Animate the appearance
      childrenRows.forEach((row, index) => {
        requestAnimationFrame(() => {
          row.style.opacity = '0'
          row.style.transform = 'translateY(-10px)'
          row.style.transition = `opacity 0.2s ease-out ${index * 0.05}s, transform 0.2s ease-out ${index * 0.05}s`

          requestAnimationFrame(() => {
            row.style.opacity = '1'
            row.style.transform = 'translateY(0)'
          })
        })
      })

    } else {
      // Collapse: hide children and reset chevron
      if (chevron) {
        chevron.classList.remove('rotate-90')
      }

      // Remove visual feedback from button
      button.classList.remove('bg-blue-100')
      button.classList.add('bg-gray-100')

      // Animate the disappearance
      childrenRows.forEach((row, index) => {
        row.style.transition = `opacity 0.15s ease-in ${index * 0.02}s, transform 0.15s ease-in ${index * 0.02}s`
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
          `tr.span-children[data-parent-span-id="${row.dataset.spanId}"]`
        )
        grandchildrenRows.forEach(grandchildRow => {
          grandchildRow.classList.add('hidden')
          grandchildRow.style.opacity = ''
          grandchildRow.style.transform = ''
          grandchildRow.style.transition = ''
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
        `tr.span-children[data-parent-span-id="${spanId}"]`
      )

      if (childrenRows.length > 0 && childrenRows[0].classList.contains('hidden')) {
        // Simulate click to expand
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
        `tr.span-children[data-parent-span-id="${spanId}"]`
      )

      if (childrenRows.length > 0 && !childrenRows[0].classList.contains('hidden')) {
        // Simulate click to collapse
        button.click()
      }
    })
  }

  trackExpansionState(spanId, wasExpanded) {
    // Optional: Track which spans are expanded for analytics or persistence
    const state = wasExpanded ? 'expanded' : 'collapsed'
    console.debug(`Span ${spanId} ${state}`)

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
          // Expand if collapsed
          event.preventDefault()
          if (event.target.querySelector('svg:not(.rotate-90)')) {
            event.target.click()
          }
          break
        case 'ArrowLeft':
          // Collapse if expanded
          event.preventDefault()
          if (event.target.querySelector('svg.rotate-90')) {
            event.target.click()
          }
          break
      }
    }
  }
}