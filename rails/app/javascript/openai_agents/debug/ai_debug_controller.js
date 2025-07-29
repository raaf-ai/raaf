import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modelType", "modelId", "objectSection", "executeButton", "selectedClass", "agentButton", "modelSelect", "executeForm", "stopForm", "executeButtonContainer"]

  connect() {
    console.log("AI Debug controller connected")
    console.log("Available targets:", {
      modelType: this.hasModelTypeTarget,
      modelId: this.hasModelIdTarget,
      objectSection: this.hasObjectSectionTarget,
      executeButton: this.hasExecuteButtonTarget,
      selectedClass: this.hasSelectedClassTarget
    })
    
    // Debug: Check if we can find the selects manually
    const modelTypeSelect = this.element.querySelector('select[name="model_type"]')
    const modelIdSelect = this.element.querySelector('select[name="model_id"]')
    console.log("Manual select search:", {
      modelType: modelTypeSelect,
      modelId: modelIdSelect
    })
  }

  updateObjectRequirement(event) {
    const className = event.target.value
    
    // Update the hidden field with the selected class
    if (this.hasSelectedClassTarget) {
      this.selectedClassTarget.value = className
    }
    
    // Some prompts/agents might not require an object
    // For now, we'll always show the object section
    // This could be enhanced to check specific requirements
  }

  async loadObjects(event) {
    console.log("loadObjects called", event.target.value)
    const modelType = event.target.value
    
    if (!this.hasModelIdTarget) {
      console.error("modelId target not found!")
      return
    }
    
    const modelIdSelect = this.modelIdTarget
    console.log("Found modelId select:", modelIdSelect)
    
    if (!modelType) {
      modelIdSelect.disabled = true
      modelIdSelect.innerHTML = '<option value="">-- Select object --</option>'
      return
    }

    // Remove any manual input fields that might have been added
    const existingInput = modelIdSelect.parentNode.querySelector('input[name="model_id"]')
    if (existingInput) {
      existingInput.remove()
      modelIdSelect.style.display = ''
    }

    // Show loading state
    modelIdSelect.disabled = false
    modelIdSelect.innerHTML = '<option value="">Loading...</option>'
    
    // Fetch objects for the selected type
    try {
      console.log(`Fetching objects for type: ${modelType}`)
      const response = await fetch(`/ai_debug/prompts/objects?model_type=${encodeURIComponent(modelType)}`)
      console.log('Response status:', response.status)
      
      if (!response.ok) {
        const errorText = await response.text()
        console.error('Response error:', errorText)
        throw new Error(`Failed to load objects: ${response.status}`)
      }
      
      const data = await response.json()
      
      // Clear existing options and add new ones
      modelIdSelect.disabled = false
      modelIdSelect.innerHTML = ''
      
      // Add default option
      const defaultOption = document.createElement('option')
      defaultOption.value = ''
      defaultOption.textContent = data.length === 0 ? 'No objects found' : '-- Select object --'
      modelIdSelect.appendChild(defaultOption)
      
      if (data.length === 0) {
        return
      }
      
      // Populate the select with objects
      data.forEach(obj => {
        const option = document.createElement('option')
        option.value = obj.id
        
        // Build display text based on available fields
        let displayText = `#${obj.id} - ${obj.name || 'Unnamed'}`
        if (obj.company) {
          displayText += ` (${obj.company})`
        } else if (obj.type) {
          displayText += ` [${obj.type || 'Company'}]`
        }
        
        option.textContent = displayText
        modelIdSelect.appendChild(option)
      })
      
      // If using Preline's custom select, we may need to refresh it
      if (window.HSSelect && modelIdSelect.closest('[data-hs-select]')) {
        const selectInstance = window.HSSelect.getInstance(modelIdSelect.closest('[data-hs-select]'))
        if (selectInstance) {
          selectInstance.destroy()
          new window.HSSelect(modelIdSelect.closest('[data-hs-select]'))
        }
      }
    } catch (error) {
      console.error('Error loading objects:', error)
      modelIdSelect.disabled = true
      modelIdSelect.innerHTML = '<option value="">Error loading objects</option>'
    }
  }

  prepareSubmit(event) {
    console.log("Preparing form submission")
    
    // Get the selected prompt class
    const promptSelect = document.querySelector('select[name="class_name"]')
    const className = promptSelect ? promptSelect.value : ""
    
    console.log(`Submitting prompt with class: ${className}`)
    
    // Update the hidden field
    if (this.hasSelectedClassTarget) {
      this.selectedClassTarget.value = className
    }
    
    // Show loading state
    this.showLoadingState()
  }
  
  showLoadingState() {
    // Disable the submit button and show loading text
    if (this.hasExecuteButtonTarget) {
      const button = this.executeButtonTarget
      button.disabled = true
      
      // Store original button content
      this.originalButtonContent = button.innerHTML
      
      // Update button to show loading state
      button.innerHTML = `
        <span class="inline-flex items-center">
          <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
          <span>Running...</span>
        </span>
      `
    }
    
    // Don't disable the form for regular submissions
    // The form will be replaced by the server response
  }
  
  hideLoadingState() {
    // Re-enable the submit button and restore original text
    if (this.hasExecuteButtonTarget && this.originalButtonContent) {
      const button = this.executeButtonTarget
      button.disabled = false
      button.innerHTML = this.originalButtonContent
    }
    
    // Remove loading overlay from the form
    const form = this.element.querySelector('form')
    if (form) {
      form.classList.remove('opacity-75', 'pointer-events-none')
    }
  }

  showAgentLoadingState(event) {
    console.log("showAgentLoadingState called")
    
    // Update the button in the execute form to show loading state
    if (this.hasAgentButtonTarget) {
      const button = this.agentButtonTarget
      button.disabled = true
      
      // Store original button content
      this.originalAgentButtonContent = button.innerHTML
      
      // Update button to show loading state
      button.innerHTML = `
        <span class="inline-flex items-center">
          <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
          <span>Running Agent...</span>
        </span>
      `
    }
    
    // Don't switch buttons here - wait for the WebSocket connection to confirm start
    // The form submission continues naturally
  }
  
  showStopButton() {
    console.log("showStopButton called")
    // This method can be called from the streaming controller
    if (this.hasExecuteFormTarget && this.hasStopFormTarget) {
      console.log("Hiding execute form, showing stop form")
      this.executeFormTarget.style.display = 'none'
      this.stopFormTarget.style.display = 'block'
      this.stopFormTarget.classList.remove('hidden')
    }
  }
  
  hideStopButton() {
    console.log("hideStopButton called")
    // This method can be called from the streaming controller
    if (this.hasExecuteFormTarget && this.hasStopFormTarget) {
      console.log("Hiding stop form, showing execute form")
      this.stopFormTarget.style.display = 'none'
      this.stopFormTarget.classList.add('hidden')
      this.executeFormTarget.style.display = 'block'
      
      // Reset the execute button to its original state
      if (this.hasAgentButtonTarget && this.originalAgentButtonContent) {
        this.agentButtonTarget.disabled = false
        this.agentButtonTarget.innerHTML = this.originalAgentButtonContent
      }
    }
  }
  
  handleResponse(event) {
    // The response will be handled by Turbo, but we can add any
    // additional client-side processing here if needed
    console.log("AI Debug execution completed")
  }
  
  async stopExecution(event) {
    console.log("Stopping execution")
    const button = event.currentTarget
    const sessionId = button.dataset.sessionId
    
    // Disable the button to prevent multiple clicks
    button.disabled = true
    
    try {
      // Send stop request via fetch to avoid page navigation
      const response = await fetch('/ai_debug/prompts/stop_execution', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ session_id: sessionId })
      })
      
      if (response.ok) {
        console.log("Stop request sent successfully")
        // The WebSocket will handle the UI updates via the "stopped" message
      } else {
        console.error("Failed to stop execution")
        button.disabled = false
      }
    } catch (error) {
      console.error("Error stopping execution:", error)
      button.disabled = false
    }
  }
  
  updateModelOptions(event) {
    const provider = event.target.value
    const modelSelect = this.hasModelSelectTarget ? this.modelSelectTarget : document.getElementById('model_override')
    
    if (!modelSelect) {
      console.error('Model select element not found')
      return
    }
    
    // Store current selection to try to preserve it
    const currentValue = modelSelect.value
    
    // Hide all optgroups and their options first
    modelSelect.querySelectorAll('optgroup').forEach(group => {
      group.style.display = 'none'
      // Also disable all options within hidden groups
      group.querySelectorAll('option').forEach(option => {
        option.style.display = 'none'
        option.disabled = true
      })
    })
    
    // Reset selection
    modelSelect.value = ''
    
    // Show the appropriate provider's optgroup
    if (provider) {
      const providerGroup = modelSelect.querySelector(`optgroup[data-provider="${provider}"]`)
      if (providerGroup) {
        providerGroup.style.display = ''
        // Enable all options in this group
        providerGroup.querySelectorAll('option').forEach(option => {
          option.style.display = ''
          option.disabled = false
        })
        
        // Try to preserve selection if it belongs to this provider
        if (currentValue && providerGroup.querySelector(`option[value="${currentValue}"]`)) {
          modelSelect.value = currentValue
        } else {
          // Otherwise select first option in the group
          const firstOption = providerGroup.querySelector('option')
          if (firstOption) {
            modelSelect.value = firstOption.value
          }
        }
      }
    } else {
      // No provider selected - show OpenAI by default
      const openaiGroup = modelSelect.querySelector('optgroup[data-provider="openai"]')
      if (openaiGroup) {
        openaiGroup.style.display = ''
        openaiGroup.querySelectorAll('option').forEach(option => {
          option.style.display = ''
          option.disabled = false
        })
      }
      // Keep the default option selected
      const defaultOption = modelSelect.querySelector('option[value=""]')
      if (defaultOption) {
        defaultOption.style.display = ''
        defaultOption.disabled = false
      }
    }
    
    // Trigger change event to update any dependent elements
    modelSelect.dispatchEvent(new Event('change'))
  }
}