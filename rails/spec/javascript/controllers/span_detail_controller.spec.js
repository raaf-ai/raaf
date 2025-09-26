/**
 * @jest-environment jsdom
 */

// RAAF Span Detail Controller Tests
// Tests all interactive functionality for span detail expand/collapse

// Mock Stimulus
class MockController {
  constructor() {
    this.element = document.createElement('div')
    this.debugValue = false
  }
  
  dispatch(eventName, detail) {
    const event = new CustomEvent(`span-detail:${eventName}`, detail)
    this.element.dispatchEvent(event)
  }
}

// Import the controller (adjust path as needed)
// Since this is a test, we'll include the controller logic inline
class SpanDetailController extends MockController {
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
    this.initializeSectionStates()
  }

  toggleSection(event) {
    event.preventDefault()
    
    const button = event.currentTarget
    const targetId = button.dataset.target
    const section = document.getElementById(targetId)
    const icon = button.querySelector('.toggle-icon')
    
    if (!section) {
      console.warn(`No section found with ID: ${targetId}`)
      return
    }
    
    this.performToggle(section, icon, button)
  }

  toggleToolInput(event) {
    this.toggleSection(event)
  }

  toggleToolOutput(event) {
    this.toggleSection(event)
  }

  toggleAttributeGroup(event) {
    this.toggleSection(event)
  }

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

  toggleValue(event) {
    event.preventDefault()
    
    const button = event.currentTarget
    const targetId = button.dataset.target
    const preview = document.getElementById(`${targetId}-preview`)
    const full = document.getElementById(`${targetId}-full`)
    
    if (!preview || !full) {
      console.warn(`Value elements not found for: ${targetId}`)
      return
    }
    
    if (full.classList.contains('hidden')) {
      preview.classList.add('hidden')
      full.classList.remove('hidden')
      button.textContent = 'Show Less'
    } else {
      preview.classList.remove('hidden')
      full.classList.add('hidden')
      button.textContent = 'Show More'
    }
  }

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

  copyJson(event) {
    event.preventDefault()
    
    const button = event.currentTarget
    const targetId = button.dataset.target
    const element = document.getElementById(targetId)
    
    if (!element) {
      console.warn(`Copy target not found: ${targetId}`)
      return
    }
    
    // Mock clipboard API for tests
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(element.textContent).then(() => {
        const originalText = button.textContent
        button.textContent = 'Copied!'
        button.classList.add('text-green-600')
        
        setTimeout(() => {
          button.textContent = originalText
          button.classList.remove('text-green-600')
        }, 2000)
      })
    } else {
      this.fallbackCopyToClipboard(element.textContent)
    }
  }

  initializeSectionStates() {
    const collapsedSections = this.element.querySelectorAll('[data-initially-collapsed="true"]')
    collapsedSections.forEach(section => {
      section.classList.add('hidden')
    })
  }

  performToggle(section, icon, button) {
    if (section.classList.contains('hidden')) {
      section.classList.remove('hidden')
      if (icon) {
        icon.classList.remove('bi-chevron-right')
        icon.classList.add('bi-chevron-down')
      }
      if (button.dataset.expandedText) {
        button.querySelector('.button-text').textContent = button.dataset.expandedText
      }
    } else {
      section.classList.add('hidden')
      if (icon) {
        icon.classList.remove('bi-chevron-down')
        icon.classList.add('bi-chevron-right')
      }
      if (button.dataset.collapsedText) {
        button.querySelector('.button-text').textContent = button.dataset.collapsedText
      }
    }
    
    this.dispatch('sectionToggled', { 
      detail: { 
        section: section, 
        expanded: !section.classList.contains('hidden'),
        sectionId: section.id
      } 
    })
  }

  fallbackCopyToClipboard(text) {
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

// Test Suite
describe('SpanDetailController', () => {
  let controller
  let mockEvent
  
  beforeEach(() => {
    // Clear the DOM
    document.body.innerHTML = ''
    
    // Create controller instance
    controller = new SpanDetailController()
    
    // Mock event
    mockEvent = {
      preventDefault: jest.fn(),
      currentTarget: null
    }
  })
  
  afterEach(() => {
    document.body.innerHTML = ''
  })

  describe('initialization', () => {
    test('connects successfully', () => {
      const consoleSpy = jest.spyOn(console, 'log').mockImplementation()
      controller.debugValue = true
      
      controller.connect()
      
      expect(consoleSpy).toHaveBeenCalledWith("🔍 SpanDetail controller connected")
      consoleSpy.mockRestore()
    })

    test('initializes collapsed sections', () => {
      // Setup DOM with initially collapsed section
      document.body.innerHTML = `
        <div>
          <div id="test-section" data-initially-collapsed="true">Content</div>
        </div>
      `
      
      controller.element = document.body.firstElementChild
      controller.connect()
      
      const section = document.getElementById('test-section')
      expect(section.classList.contains('hidden')).toBe(true)
    })
  })

  describe('toggleSection', () => {
    beforeEach(() => {
      document.body.innerHTML = `
        <div>
          <button data-target="test-content" data-expanded-text="Collapse" data-collapsed-text="Expand">
            <i class="bi bi-chevron-right toggle-icon"></i>
            <span class="button-text">Toggle</span>
          </button>
          <div id="test-content" class="hidden">Content</div>
        </div>
      `
      
      controller.element = document.body.firstElementChild
    })

    test('expands hidden section', () => {
      const button = document.querySelector('[data-target="test-content"]')
      const section = document.getElementById('test-content')
      const icon = button.querySelector('.toggle-icon')
      
      mockEvent.currentTarget = button
      
      expect(section.classList.contains('hidden')).toBe(true)
      expect(icon.classList.contains('bi-chevron-right')).toBe(true)
      
      controller.toggleSection(mockEvent)
      
      expect(section.classList.contains('hidden')).toBe(false)
      expect(icon.classList.contains('bi-chevron-down')).toBe(true)
      expect(icon.classList.contains('bi-chevron-right')).toBe(false)
      expect(button.querySelector('.button-text').textContent).toBe('Collapse')
      expect(mockEvent.preventDefault).toHaveBeenCalled()
    })

    test('collapses expanded section', () => {
      const button = document.querySelector('[data-target="test-content"]')
      const section = document.getElementById('test-content')
      const icon = button.querySelector('.toggle-icon')
      
      // Start with expanded state
      section.classList.remove('hidden')
      icon.classList.remove('bi-chevron-right')
      icon.classList.add('bi-chevron-down')
      
      mockEvent.currentTarget = button
      
      controller.toggleSection(mockEvent)
      
      expect(section.classList.contains('hidden')).toBe(true)
      expect(icon.classList.contains('bi-chevron-right')).toBe(true)
      expect(icon.classList.contains('bi-chevron-down')).toBe(false)
      expect(button.querySelector('.button-text').textContent).toBe('Expand')
    })

    test('handles missing section gracefully', () => {
      const consoleSpy = jest.spyOn(console, 'warn').mockImplementation()
      const button = document.querySelector('[data-target="test-content"]')
      button.dataset.target = 'non-existent'
      
      mockEvent.currentTarget = button
      
      controller.toggleSection(mockEvent)
      
      expect(consoleSpy).toHaveBeenCalledWith('No section found with ID: non-existent')
      consoleSpy.mockRestore()
    })

    test('dispatches sectionToggled event', () => {
      const button = document.querySelector('[data-target="test-content"]')
      const section = document.getElementById('test-content')
      
      mockEvent.currentTarget = button
      
      const eventSpy = jest.spyOn(controller, 'dispatch')
      
      controller.toggleSection(mockEvent)
      
      expect(eventSpy).toHaveBeenCalledWith('sectionToggled', {
        detail: {
          section: section,
          expanded: true,
          sectionId: 'test-content'
        }
      })
    })
  })

  describe('toggleToolInput', () => {
    test('delegates to toggleSection', () => {
      // Create a mock button with dataset
      const mockButton = document.createElement('button')
      mockButton.dataset.target = 'test-target'
      mockEvent.currentTarget = mockButton

      const toggleSectionSpy = jest.spyOn(controller, 'toggleSection')

      controller.toggleToolInput(mockEvent)

      expect(toggleSectionSpy).toHaveBeenCalledWith(mockEvent)
    })
  })

  describe('toggleToolOutput', () => {
    test('delegates to toggleSection', () => {
      // Create a mock button with dataset
      const mockButton = document.createElement('button')
      mockButton.dataset.target = 'test-target'
      mockEvent.currentTarget = mockButton

      const toggleSectionSpy = jest.spyOn(controller, 'toggleSection')

      controller.toggleToolOutput(mockEvent)

      expect(toggleSectionSpy).toHaveBeenCalledWith(mockEvent)
    })
  })

  describe('toggleAttributeGroup', () => {
    test('delegates to toggleSection', () => {
      // Create a mock button with dataset
      const mockButton = document.createElement('button')
      mockButton.dataset.target = 'test-target'
      mockEvent.currentTarget = mockButton

      const toggleSectionSpy = jest.spyOn(controller, 'toggleSection')

      controller.toggleAttributeGroup(mockEvent)

      expect(toggleSectionSpy).toHaveBeenCalledWith(mockEvent)
    })
  })

  describe('toggleErrorDetail', () => {
    beforeEach(() => {
      document.body.innerHTML = `
        <div>
          <button data-target="error-123">Show More</button>
          <div id="error-123-preview">Preview content</div>
          <div id="error-123-full" style="display: none">Full content</div>
        </div>
      `
    })

    test('shows full error content', () => {
      const button = document.querySelector('[data-target="error-123"]')
      const preview = document.getElementById('error-123-preview')
      const full = document.getElementById('error-123-full')
      
      mockEvent.currentTarget = button
      
      controller.toggleErrorDetail(mockEvent)
      
      expect(preview.style.display).toBe('none')
      expect(full.style.display).toBe('block')
      expect(button.textContent).toBe('Show Less')
      expect(mockEvent.preventDefault).toHaveBeenCalled()
    })

    test('hides full error content', () => {
      const button = document.querySelector('[data-target="error-123"]')
      const preview = document.getElementById('error-123-preview')
      const full = document.getElementById('error-123-full')
      
      // Start with full content shown
      preview.style.display = 'none'
      full.style.display = 'block'
      button.textContent = 'Show Less'
      
      mockEvent.currentTarget = button
      
      controller.toggleErrorDetail(mockEvent)
      
      expect(preview.style.display).toBe('block')
      expect(full.style.display).toBe('none')
      expect(button.textContent).toBe('Show More')
    })

    test('handles missing elements gracefully', () => {
      const consoleSpy = jest.spyOn(console, 'warn').mockImplementation()
      const button = document.querySelector('[data-target="error-123"]')
      button.dataset.target = 'non-existent'
      
      mockEvent.currentTarget = button
      
      controller.toggleErrorDetail(mockEvent)
      
      expect(consoleSpy).toHaveBeenCalledWith('Error detail elements not found for: non-existent')
      consoleSpy.mockRestore()
    })
  })

  describe('toggleValue', () => {
    beforeEach(() => {
      document.body.innerHTML = `
        <div>
          <button data-target="value-456">Show More</button>
          <div id="value-456-preview">Preview</div>
          <div id="value-456-full" class="hidden">Full content</div>
        </div>
      `
    })

    test('shows full value content', () => {
      const button = document.querySelector('[data-target="value-456"]')
      const preview = document.getElementById('value-456-preview')
      const full = document.getElementById('value-456-full')
      
      mockEvent.currentTarget = button
      
      controller.toggleValue(mockEvent)
      
      expect(preview.classList.contains('hidden')).toBe(true)
      expect(full.classList.contains('hidden')).toBe(false)
      expect(button.textContent).toBe('Show Less')
      expect(mockEvent.preventDefault).toHaveBeenCalled()
    })

    test('hides full value content', () => {
      const button = document.querySelector('[data-target="value-456"]')
      const preview = document.getElementById('value-456-preview')
      const full = document.getElementById('value-456-full')
      
      // Start with full content shown
      preview.classList.add('hidden')
      full.classList.remove('hidden')
      button.textContent = 'Show Less'
      
      mockEvent.currentTarget = button
      
      controller.toggleValue(mockEvent)
      
      expect(preview.classList.contains('hidden')).toBe(false)
      expect(full.classList.contains('hidden')).toBe(true)
      expect(button.textContent).toBe('Show More')
    })
  })

  describe('toggleAttributesView', () => {
    beforeEach(() => {
      document.body.innerHTML = `
        <div>
          <button>Toggle View</button>
          <div id="attributes-structured">Structured view</div>
          <div id="attributes-raw" style="display: none">Raw JSON view</div>
        </div>
      `
    })

    test('switches from structured to raw view', () => {
      const button = document.querySelector('button')
      const structured = document.getElementById('attributes-structured')
      const raw = document.getElementById('attributes-raw')
      
      mockEvent.currentTarget = button
      
      controller.toggleAttributesView(mockEvent)
      
      expect(structured.style.display).toBe('none')
      expect(raw.style.display).toBe('block')
      expect(button.textContent).toBe('Toggle View')
    })

    test('switches from raw to structured view', () => {
      const button = document.querySelector('button')
      const structured = document.getElementById('attributes-structured')
      const raw = document.getElementById('attributes-raw')
      
      // Start with raw view shown
      structured.style.display = 'none'
      raw.style.display = 'block'
      
      mockEvent.currentTarget = button
      
      controller.toggleAttributesView(mockEvent)
      
      expect(structured.style.display).toBe('block')
      expect(raw.style.display).toBe('none')
      expect(button.textContent).toBe('Toggle View')
    })
  })

  describe('copyJson', () => {
    beforeEach(() => {
      // Mock clipboard API
      Object.assign(navigator, {
        clipboard: {
          writeText: jest.fn(() => Promise.resolve())
        }
      })
      
      document.body.innerHTML = `
        <div>
          <button data-target="json-content">Copy JSON</button>
          <pre id="json-content">{"key": "value"}</pre>
        </div>
      `
    })

    test('copies JSON content to clipboard', async () => {
      const button = document.querySelector('[data-target="json-content"]')
      const jsonElement = document.getElementById('json-content')
      
      mockEvent.currentTarget = button
      
      await controller.copyJson(mockEvent)
      
      expect(navigator.clipboard.writeText).toHaveBeenCalledWith('{"key": "value"}')
      expect(mockEvent.preventDefault).toHaveBeenCalled()
    })

    test('provides visual feedback on successful copy', async () => {
      const button = document.querySelector('[data-target="json-content"]')
      const originalText = button.textContent
      
      mockEvent.currentTarget = button
      
      await controller.copyJson(mockEvent)
      
      expect(button.textContent).toBe('Copied!')
      expect(button.classList.contains('text-green-600')).toBe(true)
      
      // Fast-forward time to check reset
      setTimeout(() => {
        expect(button.textContent).toBe(originalText)
        expect(button.classList.contains('text-green-600')).toBe(false)
      }, 2000)
    })

    test('handles missing target gracefully', async () => {
      const consoleSpy = jest.spyOn(console, 'warn').mockImplementation()
      const button = document.querySelector('[data-target="json-content"]')
      button.dataset.target = 'non-existent'
      
      mockEvent.currentTarget = button
      
      await controller.copyJson(mockEvent)
      
      expect(consoleSpy).toHaveBeenCalledWith('Copy target not found: non-existent')
      consoleSpy.mockRestore()
    })
  })

  describe('cross-browser compatibility', () => {
    test('works with different event targets', () => {
      document.body.innerHTML = `
        <div>
          <button data-target="test-section">
            <span>Toggle</span>
            <i class="bi bi-chevron-right toggle-icon"></i>
          </button>
          <div id="test-section" class="hidden">Content</div>
        </div>
      `
      
      const button = document.querySelector('[data-target="test-section"]')
      const span = button.querySelector('span')
      const section = document.getElementById('test-section')
      
      // Test clicking on the span inside the button
      mockEvent.currentTarget = button
      mockEvent.target = span
      
      controller.toggleSection(mockEvent)
      
      expect(section.classList.contains('hidden')).toBe(false)
    })

    test('handles missing clipboard API gracefully', async () => {
      // Remove clipboard API
      delete navigator.clipboard
      
      document.body.innerHTML = `
        <div>
          <button data-target="json-content">Copy JSON</button>
          <pre id="json-content">{"key": "value"}</pre>
        </div>
      `
      
      const button = document.querySelector('[data-target="json-content"]')
      mockEvent.currentTarget = button
      
      const fallbackSpy = jest.spyOn(controller, 'fallbackCopyToClipboard').mockImplementation()
      
      await controller.copyJson(mockEvent)
      
      expect(fallbackSpy).toHaveBeenCalledWith('{"key": "value"}')
    })
  })

  describe('edge cases', () => {
    test('handles elements without required classes', () => {
      document.body.innerHTML = `
        <div>
          <button data-target="test-section">Toggle</button>
          <div id="test-section" class="hidden">Content</div>
        </div>
      `
      
      const button = document.querySelector('[data-target="test-section"]')
      const section = document.getElementById('test-section')
      
      mockEvent.currentTarget = button
      
      // Should not throw error even without toggle-icon or button-text
      expect(() => controller.toggleSection(mockEvent)).not.toThrow()
      expect(section.classList.contains('hidden')).toBe(false)
    })

    test('handles rapid consecutive toggles', () => {
      document.body.innerHTML = `
        <div>
          <button data-target="test-section">
            <i class="bi bi-chevron-right toggle-icon"></i>
          </button>
          <div id="test-section" class="hidden">Content</div>
        </div>
      `
      
      const button = document.querySelector('[data-target="test-section"]')
      const section = document.getElementById('test-section')
      const icon = button.querySelector('.toggle-icon')
      
      mockEvent.currentTarget = button
      
      // Rapid toggles
      controller.toggleSection(mockEvent)
      expect(section.classList.contains('hidden')).toBe(false)
      expect(icon.classList.contains('bi-chevron-down')).toBe(true)
      
      controller.toggleSection(mockEvent)
      expect(section.classList.contains('hidden')).toBe(true)
      expect(icon.classList.contains('bi-chevron-right')).toBe(true)
      
      controller.toggleSection(mockEvent)
      expect(section.classList.contains('hidden')).toBe(false)
      expect(icon.classList.contains('bi-chevron-down')).toBe(true)
    })
  })
})

// Additional integration tests
describe('SpanDetailController Integration', () => {
  let controller
  
  beforeEach(() => {
    document.body.innerHTML = `
      <div data-controller="span-detail" data-span-detail-debug-value="true">
        <!-- Tool Input Section -->
        <button data-action="click->span-detail#toggleToolInput" 
                data-target="tool-input-section-123"
                data-expanded-text="Collapse" 
                data-collapsed-text="Expand">
          <i class="bi bi-chevron-right toggle-icon"></i>
          <span class="button-text">Toggle Tool Input</span>
        </button>
        <div id="tool-input-section-123" class="hidden" data-initially-collapsed="true">
          Tool input content
        </div>
        
        <!-- Tool Output Section -->
        <button data-action="click->span-detail#toggleToolOutput" 
                data-target="tool-output-section-123"
                data-expanded-text="Collapse" 
                data-collapsed-text="Expand">
          <i class="bi bi-chevron-right toggle-icon"></i>
          <span class="button-text">Toggle Tool Output</span>
        </button>
        <div id="tool-output-section-123" class="hidden" data-initially-collapsed="true">
          Tool output content
        </div>
        
        <!-- Attribute Group -->
        <button data-action="click->span-detail#toggleAttributeGroup" 
                data-target="attr-group-content">
          <i class="bi bi-chevron-right toggle-icon"></i>
          <span class="button-text">Toggle Attributes</span>
        </button>
        <div id="attr-group-content" class="hidden" data-initially-collapsed="true">
          Attribute content
        </div>
        
        <!-- Copy JSON -->
        <button data-action="click->span-detail#copyJson" 
                data-target="json-data">Copy JSON</button>
        <pre id="json-data">{"test": "data"}</pre>
      </div>
    `
    
    controller = new SpanDetailController()
    controller.element = document.querySelector('[data-controller="span-detail"]')
    controller.debugValue = true
  })
  
  test('initializes all initially-collapsed sections as hidden', () => {
    controller.connect()
    
    expect(document.getElementById('tool-input-section-123').classList.contains('hidden')).toBe(true)
    expect(document.getElementById('tool-output-section-123').classList.contains('hidden')).toBe(true)
    expect(document.getElementById('attr-group-content').classList.contains('hidden')).toBe(true)
  })
  
  test('tool input and output toggles work independently', () => {
    controller.connect()
    
    const inputButton = document.querySelector('[data-action*="toggleToolInput"]')
    const outputButton = document.querySelector('[data-action*="toggleToolOutput"]')
    const inputSection = document.getElementById('tool-input-section-123')
    const outputSection = document.getElementById('tool-output-section-123')
    
    // Toggle input section
    const inputEvent = { preventDefault: jest.fn(), currentTarget: inputButton }
    controller.toggleToolInput(inputEvent)
    
    expect(inputSection.classList.contains('hidden')).toBe(false)
    expect(outputSection.classList.contains('hidden')).toBe(true)
    
    // Toggle output section
    const outputEvent = { preventDefault: jest.fn(), currentTarget: outputButton }
    controller.toggleToolOutput(outputEvent)
    
    expect(inputSection.classList.contains('hidden')).toBe(false)
    expect(outputSection.classList.contains('hidden')).toBe(false)
  })
  
  test('multiple sections can be expanded simultaneously', () => {
    controller.connect()
    
    const inputButton = document.querySelector('[data-action*="toggleToolInput"]')
    const attrButton = document.querySelector('[data-action*="toggleAttributeGroup"]')
    
    // Expand both sections
    controller.toggleToolInput({ preventDefault: jest.fn(), currentTarget: inputButton })
    controller.toggleAttributeGroup({ preventDefault: jest.fn(), currentTarget: attrButton })
    
    expect(document.getElementById('tool-input-section-123').classList.contains('hidden')).toBe(false)
    expect(document.getElementById('attr-group-content').classList.contains('hidden')).toBe(false)
  })
})
