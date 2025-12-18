// RAAF Replay Form Stimulus Controller
// Handles replay configuration form interactions including sliders and submission
import { Controller } from "@hotwired/stimulus"

// Try to import Turbo, but also check for global availability
let Turbo = null
try {
  // Try dynamic import or check global
  if (typeof window !== 'undefined' && window.Turbo) {
    Turbo = window.Turbo
  }
} catch (e) {
  // Will use global Turbo if available
}

// Helper to get Turbo instance (module or global)
const getTurbo = () => {
  if (Turbo) return Turbo
  if (typeof window !== 'undefined' && window.Turbo) return window.Turbo
  return null
}

export default class extends Controller {
  static targets = [
    "provider",
    "model",
    "temperature",
    "temperatureValue",
    "maxTokens",
    "topP",
    "topPValue",
    "frequencyPenalty",
    "frequencyPenaltyValue",
    "presencePenalty",
    "presencePenaltyValue"
  ]

  static values = {
    submitUrl: String,
    spanId: String,
    debug: { type: Boolean, default: false }
  }

  connect() {
    if (this.debugValue) {
      console.log("Replay form controller connected")
    }

    // Initialize model filtering based on current provider selection
    if (this.hasProviderTarget && this.hasModelTarget) {
      this.updateModelOptions()
    }
  }

  // Model definitions by provider
  static models = {
    openai: [
      // GPT-5 Series (Latest)
      { value: "gpt-5", label: "GPT-5" },
      // GPT-4.1 Series (April 2025)
      { value: "gpt-4.1", label: "GPT-4.1" },
      { value: "gpt-4.1-mini", label: "GPT-4.1 Mini" },
      { value: "gpt-4.1-nano", label: "GPT-4.1 Nano" },
      // GPT-4o Series
      { value: "gpt-4o", label: "GPT-4o" },
      { value: "gpt-4o-mini", label: "GPT-4o Mini" },
      { value: "gpt-4-turbo", label: "GPT-4 Turbo" },
      // O-Series Reasoning Models
      { value: "o3-pro", label: "O3 Pro" },
      { value: "o3", label: "O3" },
      { value: "o4-mini", label: "O4 Mini" },
      { value: "o1-preview", label: "O1 Preview" },
      { value: "o1-mini", label: "O1 Mini" },
      { value: "o3-mini", label: "O3 Mini" }
    ],
    anthropic: [
      { value: "claude-sonnet-4-20250514", label: "Claude 4 Sonnet" },
      { value: "claude-3-5-sonnet-20241022", label: "Claude 3.5 Sonnet" },
      { value: "claude-3-opus-20240229", label: "Claude 3 Opus" },
      { value: "claude-3-5-haiku-20241022", label: "Claude 3.5 Haiku" }
    ],
    google: [
      { value: "gemini-2.5-pro-preview-06-05", label: "Gemini 2.5 Pro" },
      { value: "gemini-2.5-flash-preview-05-20", label: "Gemini 2.5 Flash" },
      { value: "gemini-2.0-flash", label: "Gemini 2.0 Flash" },
      { value: "gemini-2.0-flash-lite", label: "Gemini 2.0 Flash Lite" },
      { value: "gemini-1.5-pro-latest", label: "Gemini 1.5 Pro" },
      { value: "gemini-1.5-flash-latest", label: "Gemini 1.5 Flash" }
    ],
    perplexity: [
      { value: "sonar-pro", label: "Sonar Pro" },
      { value: "sonar", label: "Sonar" },
      { value: "sonar-reasoning-pro", label: "Sonar Reasoning Pro" },
      { value: "sonar-reasoning", label: "Sonar Reasoning" }
    ],
    groq: [
      { value: "llama-3.3-70b-versatile", label: "Llama 3.3 70B" },
      { value: "llama-3.1-70b-versatile", label: "Llama 3.1 70B" },
      { value: "llama-3.1-8b-instant", label: "Llama 3.1 8B" },
      { value: "mixtral-8x7b-32768", label: "Mixtral 8x7B" }
    ],
    xai: [
      { value: "grok-2-1212", label: "Grok 2" },
      { value: "grok-2-vision-1212", label: "Grok 2 Vision" },
      { value: "grok-beta", label: "Grok Beta" }
    ]
  }

  // Rebuild model dropdown with only models for the selected provider
  updateModelOptions() {
    if (!this.hasProviderTarget || !this.hasModelTarget) {
      return
    }

    const selectedProvider = this.providerTarget.value
    const modelSelect = this.modelTarget
    const currentModel = modelSelect.value
    const models = this.constructor.models[selectedProvider] || []

    if (this.debugValue) {
      console.log(`Updating models for provider: ${selectedProvider}`, models)
    }

    // Clear existing options
    modelSelect.innerHTML = ""

    // Add new options for the selected provider
    let selectedFound = false
    models.forEach((model, index) => {
      const option = document.createElement("option")
      option.value = model.value
      option.textContent = model.label

      // Try to preserve current selection if it exists in the new provider
      if (model.value === currentModel) {
        option.selected = true
        selectedFound = true
      } else if (index === 0 && !selectedFound) {
        // Select first option by default
        option.selected = true
      }

      modelSelect.appendChild(option)
    })

    if (this.debugValue) {
      console.log(`Model dropdown updated, selected: ${modelSelect.value}`)
    }
  }

  // Update slider value display when slider changes
  updateSliderValue(event) {
    const slider = event.currentTarget
    const name = slider.name
    const value = slider.value

    // Find the corresponding value display element
    const valueDisplay = document.getElementById(`${name}-value`)
    if (valueDisplay) {
      valueDisplay.textContent = value
    }

    if (this.debugValue) {
      console.log(`Slider ${name} updated to ${value}`)
    }
  }

  // Collect form data and submit via Turbo
  submit(event) {
    event.preventDefault()

    const formData = this.collectFormData()

    if (this.debugValue) {
      console.log("Submitting replay with data:", formData)
    }

    this.submitReplay(formData)
  }

  // Collect all form data
  collectFormData() {
    const data = {
      span_replay: {
        configuration_changes: {},
        system_prompt: null,
        user_messages: []
      }
    }

    // Collect provider and model settings
    if (this.hasProviderTarget) {
      data.span_replay.configuration_changes.provider = this.providerTarget.value
    }

    if (this.hasModelTarget) {
      data.span_replay.configuration_changes.model = this.modelTarget.value
    }

    if (this.hasTemperatureTarget) {
      data.span_replay.configuration_changes.temperature = parseFloat(this.temperatureTarget.value)
    }

    if (this.hasMaxTokensTarget) {
      data.span_replay.configuration_changes.max_tokens = parseInt(this.maxTokensTarget.value, 10)
    }

    if (this.hasTopPTarget) {
      data.span_replay.configuration_changes.top_p = parseFloat(this.topPTarget.value)
    }

    if (this.hasFrequencyPenaltyTarget) {
      data.span_replay.configuration_changes.frequency_penalty = parseFloat(this.frequencyPenaltyTarget.value)
    }

    if (this.hasPresencePenaltyTarget) {
      data.span_replay.configuration_changes.presence_penalty = parseFloat(this.presencePenaltyTarget.value)
    }

    // Collect system prompt
    const systemPrompt = document.getElementById("system_prompt")
    if (systemPrompt) {
      data.span_replay.system_prompt = systemPrompt.value
    }

    // Collect user messages
    const messagesContainer = document.getElementById("messages-container")
    if (messagesContainer) {
      const messageFields = messagesContainer.querySelectorAll("[data-message-index]")
      messageFields.forEach((field, index) => {
        const textarea = field.querySelector("textarea")
        const roleInput = field.querySelector("input[type='hidden']")
        if (textarea && roleInput) {
          data.span_replay.user_messages.push({
            role: roleInput.value,
            content: textarea.value
          })
        }
      })
    }

    // Collect notes
    const notesField = document.getElementById("notes")
    if (notesField) {
      data.span_replay.notes = notesField.value
    }

    return data
  }

  // Submit the replay request
  async submitReplay(formData) {
    const statusContainer = document.getElementById("replay-status")

    // Show loading state
    if (statusContainer) {
      statusContainer.innerHTML = `
        <div class="bg-blue-50 border border-blue-200 rounded-xl p-4">
          <div class="flex items-center">
            <div class="animate-spin mr-3">
              <i class="bi bi-arrow-repeat text-blue-600 text-xl"></i>
            </div>
            <div>
              <span class="font-medium text-blue-800">Starting replay...</span>
              <span class="ml-2 text-sm text-blue-600">Please wait while we process your request.</span>
            </div>
          </div>
        </div>
      `
    }

    try {
      // Get the form element to extract the URL
      const form = this.element.closest("form") || document.querySelector("form")
      const url = form ? form.action : this.submitUrlValue

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/vnd.turbo-stream.html, text/html, application/json",
          "X-CSRF-Token": this.getCsrfToken()
        },
        body: JSON.stringify(formData)
      })

      if (response.ok) {
        const contentType = response.headers.get("content-type")

        if (contentType && contentType.includes("text/vnd.turbo-stream.html")) {
          // Handle Turbo Stream response
          const html = await response.text()
          const turbo = getTurbo()
          if (turbo && turbo.renderStreamMessage) {
            turbo.renderStreamMessage(html)
          } else {
            // Fallback: try to parse and apply the Turbo Stream manually
            console.warn("Turbo not available, falling back to page reload")
            window.location.reload()
          }
        } else if (contentType && contentType.includes("application/json")) {
          // Handle JSON response - redirect to show page
          const result = await response.json()
          if (result.replay_id) {
            window.location.href = result.redirect_url || window.location.pathname.replace("/new", `/${result.replay_id}`)
          }
        } else {
          // Handle HTML response
          const html = await response.text()
          if (statusContainer) {
            statusContainer.innerHTML = html
          }
        }
      } else {
        throw new Error(`Request failed with status ${response.status}`)
      }
    } catch (error) {
      console.error("Replay submission failed:", error)

      if (statusContainer) {
        statusContainer.innerHTML = `
          <div class="bg-red-50 border border-red-200 rounded-xl p-4">
            <div class="flex items-center">
              <i class="bi bi-exclamation-triangle text-red-600 text-xl mr-3"></i>
              <div>
                <span class="font-medium text-red-800">Submission failed</span>
                <span class="ml-2 text-sm text-red-600">${error.message}</span>
              </div>
            </div>
          </div>
        `
      }
    }
  }

  getCsrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.getAttribute("content") : ""
  }

  disconnect() {
    if (this.debugValue) {
      console.log("Replay form controller disconnected")
    }
  }
}
