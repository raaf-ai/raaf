import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["output", "status"]
  static values = { sessionId: String }

  connect() {
    console.log("AI Debug Streaming controller connected")
    console.log("Session ID:", this.sessionIdValue)
    
    // Initialize empty log container
    this.clearOutput()
    
    // Create consumer instance
    this.consumer = createConsumer()
    console.log("Consumer created:", this.consumer)
    
    // Subscribe to the debug channel with session ID
    this.subscription = this.consumer.subscriptions.create(
      { 
        channel: "AiDebugChannel", 
        session_id: this.sessionIdValue 
      },
      {
        connected: () => {
          console.log("WebSocket connected to AiDebugChannel")
          this.updateStatus("Connected", "text-green-500")
        },

        disconnected: () => {
          console.log("WebSocket disconnected from AiDebugChannel")
          this.updateStatus("Disconnected", "text-red-500")
          this.notifyDebugController('disconnected')
        },

        received: (data) => {
          console.log("Received data:", data)
          this.handleMessage(data)
        }
      }
    )
    console.log("Subscription created:", this.subscription)
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    if (this.consumer) {
      this.consumer.disconnect()
    }
  }

  handleMessage(data) {
    switch(data.type) {
      case "start":
        this.updateStatus("Running...", "text-blue-500")
        this.appendMessage(data.message, "text-blue-600 font-semibold")
        this.notifyDebugController('start')
        break
      
      case "log":
        this.appendMessage(data.message)
        break
      
      case "complete":
        this.updateStatus("Completed", "text-green-500")
        this.appendMessage(data.message, "text-green-600 font-semibold")
        this.notifyDebugController('complete')
        break
      
      case "error":
        this.updateStatus("Error", "text-red-500")
        this.appendMessage(data.message, "text-red-600")
        this.notifyDebugController('error')
        break
        
      case "stopped":
        this.updateStatus("Stopped", "text-yellow-500")
        this.appendMessage(data.message, "text-yellow-600 font-semibold")
        this.notifyDebugController('stopped')
        break
    }
  }

  appendMessage(message, extraClasses = "") {
    if (!this.hasOutputTarget) return
    
    const line = document.createElement("div")
    line.className = `whitespace-pre-wrap ${extraClasses}`
    line.textContent = message
    
    this.outputTarget.appendChild(line)
    
    // Auto-scroll to bottom
    this.outputTarget.scrollTop = this.outputTarget.scrollHeight
  }

  clearOutput() {
    if (this.hasOutputTarget) {
      this.outputTarget.innerHTML = ""
    }
  }

  updateStatus(status, colorClass) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = status
      this.statusTarget.className = `text-sm font-medium ${colorClass}`
    }
  }
  
  notifyDebugController(status) {
    // Find all AI debug controllers and notify them of status changes
    const debugElements = document.querySelectorAll('[data-controller*="ai-debug"]')
    
    debugElements.forEach(element => {
      const debugController = this.application.getControllerForElementAndIdentifier(element, 'ai-debug')
      
      if (debugController && debugController.hasExecuteFormTarget) {
        console.log(`Notifying debug controller of status: ${status}`)
        
        switch(status) {
          case 'start':
            debugController.showStopButton()
            break
          case 'complete':
          case 'error':
          case 'stopped':
          case 'disconnected':
            debugController.hideStopButton()
            break
        }
      }
    })
  }
}