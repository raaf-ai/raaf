import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["providerSelect", "modelSelect"]

  async connect() {
    console.log("AI Debug Provider controller connected")
    await this.loadProviders()
  }

  async loadProviders() {
    try {
      const response = await fetch('/ai_debug/providers')
      if (!response.ok) throw new Error('Failed to load providers')
      
      const providers = await response.json()
      
      // Clear existing options except the default
      const select = this.providerSelectTarget
      while (select.options.length > 1) {
        select.remove(1)
      }
      
      // Add provider options
      providers.forEach(provider => {
        const option = document.createElement('option')
        option.value = provider.key
        option.textContent = provider.name
        
        // Add indicator if API key is not configured
        if (!provider.available) {
          option.textContent += ' (No API key)'
          option.disabled = true
          option.style.color = '#999'
        }
        
        select.appendChild(option)
      })
    } catch (error) {
      console.error('Error loading providers:', error)
    }
  }

  async loadModels(event) {
    const provider = event.target.value
    const modelSelect = this.modelSelectTarget
    
    // Clear existing options
    modelSelect.innerHTML = ''
    
    if (!provider) {
      // No provider selected
      modelSelect.disabled = true
      const option = document.createElement('option')
      option.value = ''
      option.textContent = 'Select a provider first'
      modelSelect.appendChild(option)
      return
    }
    
    // Show loading state
    modelSelect.disabled = true
    const loadingOption = document.createElement('option')
    loadingOption.value = ''
    loadingOption.textContent = 'Loading models...'
    modelSelect.appendChild(loadingOption)
    
    try {
      const response = await fetch(`/ai_debug/providers/${encodeURIComponent(provider)}/models`)
      if (!response.ok) throw new Error('Failed to load models')
      
      const models = await response.json()
      
      // Clear loading option
      modelSelect.innerHTML = ''
      
      // Add default option
      const defaultOption = document.createElement('option')
      defaultOption.value = ''
      defaultOption.textContent = 'Use agent default'
      modelSelect.appendChild(defaultOption)
      
      // Add model options
      models.forEach(model => {
        const option = document.createElement('option')
        option.value = model.value
        option.textContent = model.name
        
        // Add description as a data attribute for potential tooltip
        if (model.description) {
          option.setAttribute('data-description', model.description)
          option.title = model.description
        }
        
        modelSelect.appendChild(option)
      })
      
      // Enable the select
      modelSelect.disabled = false
      
    } catch (error) {
      console.error('Error loading models:', error)
      
      // Show error state
      modelSelect.innerHTML = ''
      const errorOption = document.createElement('option')
      errorOption.value = ''
      errorOption.textContent = 'Error loading models'
      modelSelect.appendChild(errorOption)
    }
  }
}