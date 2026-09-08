// Replay form — the provider and model pickers, the sampling sliders, and
// the submission that queues the replay.
//
// The form posts JSON rather than letting the browser submit it, because the
// prompt it sends is assembled from the message rows the prompt editor
// maintains in the DOM rather than from named fields.
class ReplayFormController extends Controller {
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
      { value: "gemini-3-pro-preview", label: "Gemini 3 Pro Preview" },
      { value: "gemini-3-flash-preview", label: "Gemini 3 Flash Preview" },
      { value: "gemini-2.5-pro", label: "Gemini 2.5 Pro" },
      { value: "gemini-2.5-flash", label: "Gemini 2.5 Flash" },
      { value: "gemini-2.5-flash-lite", label: "Gemini 2.5 Flash Lite" },
      { value: "gemini-2.0-flash", label: "Gemini 2.0 Flash" },
      { value: "gemini-2.0-flash-lite", label: "Gemini 2.0 Flash Lite" }
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

  connect() {
    if (this.debugValue) {
      console.log("Replay form controller connected")
    }

    // Initialize model filtering based on current provider selection
    if (this.hasProviderTarget && this.hasModelTarget) {
      this.updateModelOptions()
    }
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
      console.log("Updating models for provider:", selectedProvider, models)
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
      console.log("Model dropdown updated, selected:", modelSelect.value)
    }
  }

  // Update slider value display when slider changes
  updateSliderValue(event) {
    const slider = event.currentTarget
    const name = slider.name
    const value = slider.value

    // Find the corresponding value display element
    const valueDisplay = document.getElementById(name + "-value")
    if (valueDisplay) {
      valueDisplay.textContent = value
    }

    if (this.debugValue) {
      console.log("Slider " + name + " updated to " + value)
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
      messageFields.forEach((field) => {
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
      statusContainer.innerHTML =
        '<div class="raaf-alert raaf-alert--info" role="status">' +
          '<span class="raaf-icon"><i class="bi bi-arrow-repeat"></i></span>' +
          '<div class="raaf-alert-body">' +
            '<p class="raaf-alert-title">Starting</p>' +
            '<p class="raaf-alert-text">Queueing the replay…</p>' +
          '</div>' +
        '</div>'
    }

    try {
      // Get the form element to extract the URL
      const form = this.element.closest("form") || document.querySelector("form")
      const url = form ? form.action : this.submitUrlValue

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json, text/vnd.turbo-stream.html, text/html",
          "X-CSRF-Token": this.getCsrfToken()
        },
        body: JSON.stringify(formData)
      })

      if (response.ok) {
        const contentType = response.headers.get("content-type")

        if (contentType && contentType.includes("text/vnd.turbo-stream.html")) {
          // Handle Turbo Stream response - apply it then redirect to show page
          const html = await response.text()
          // Use window.Turbo if available (set by @hotwired/turbo-rails)
          if (typeof window !== 'undefined' && window.Turbo && window.Turbo.renderStreamMessage) {
            window.Turbo.renderStreamMessage(html)
          }

          // Extract replay_id from the turbo-stream response and redirect to show page
          // The stream HTML contains the replay ID in the target element
          const parser = new DOMParser()
          const doc = parser.parseFromString(html, 'text/html')
          const streamEl = doc.querySelector('turbo-stream')

          // Try to extract replay_id from the response
          const replayIdMatch = html.match(/replay[_-]?(\d+)/i) || html.match(/replays\/(\d+)/)
          if (replayIdMatch && replayIdMatch[1]) {
            const replayId = replayIdMatch[1]
            const currentPath = window.location.pathname
            // Convert /new to /:id in the URL path
            const showPath = currentPath.replace(/\/new$/, '/' + replayId)
            setTimeout(() => { window.location.href = showPath }, 500)
          }
        } else if (contentType && contentType.includes("application/json")) {
          // Handle JSON response - redirect to show page
          const result = await response.json()
          if (result.replay_id) {
            window.location.href = result.redirect_url || window.location.pathname.replace("/new", "/" + result.replay_id)
          }
        } else {
          // Handle HTML response
          const html = await response.text()
          if (statusContainer) {
            statusContainer.innerHTML = html
          }
        }
      } else {
        throw new Error("Request failed with status " + response.status)
      }
    } catch (error) {
      console.error("Replay submission failed:", error)

      if (statusContainer) {
        statusContainer.innerHTML =
          '<div class="raaf-alert raaf-alert--error" role="alert">' +
            '<span class="raaf-icon"><i class="bi bi-x-octagon-fill"></i></span>' +
            '<div class="raaf-alert-body">' +
              '<p class="raaf-alert-title">The replay could not be queued</p>' +
              '<p class="raaf-alert-text"></p>' +
            '</div>' +
          '</div>'
        statusContainer.querySelector(".raaf-alert-text").textContent = error.message
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
