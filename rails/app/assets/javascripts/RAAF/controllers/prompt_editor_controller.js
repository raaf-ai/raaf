// RAAF Prompt Editor Stimulus Controller
// Handles dynamic message management for replay prompt editing
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messagesContainer", "messageTemplate", "messageCount"]

  static values = {
    maxMessages: { type: Number, default: 20 },
    debug: { type: Boolean, default: false }
  }

  connect() {
    this.messageIndex = this.countMessages()
    if (this.debugValue) {
      console.log("Prompt editor controller connected", { messageCount: this.messageIndex })
    }
  }

  // Add a new user message to the list
  addMessage(event) {
    event.preventDefault()

    if (this.messageIndex >= this.maxMessagesValue) {
      this.showNotification("Maximum number of messages reached", "warning")
      return
    }

    const container = this.messagesContainerTarget
    const newMessage = this.createMessageElement(this.messageIndex, "user", "")

    container.appendChild(newMessage)
    this.messageIndex++
    this.updateMessageCount()

    // Focus the new textarea
    const textarea = newMessage.querySelector("textarea")
    if (textarea) {
      textarea.focus()
    }

    if (this.debugValue) {
      console.log("Added new message", { index: this.messageIndex - 1 })
    }
  }

  // Remove a message from the list
  removeMessage(event) {
    event.preventDefault()

    const messageElement = event.currentTarget.closest("[data-message-index]")
    if (!messageElement) return

    const index = parseInt(messageElement.dataset.messageIndex, 10)

    // Don't allow removing the last message
    if (this.countMessages() <= 1) {
      this.showNotification("At least one message is required", "warning")
      return
    }

    messageElement.remove()
    this.reindexMessages()
    this.updateMessageCount()

    if (this.debugValue) {
      console.log("Removed message", { index })
    }
  }

  // Toggle message role between user and assistant
  toggleRole(event) {
    event.preventDefault()

    const messageElement = event.currentTarget.closest("[data-message-index]")
    if (!messageElement) return

    const roleInput = messageElement.querySelector("input[type='hidden']")
    const roleDisplay = messageElement.querySelector("[data-role-display]")

    if (roleInput && roleDisplay) {
      const currentRole = roleInput.value
      const newRole = currentRole === "user" ? "assistant" : "user"

      roleInput.value = newRole
      roleDisplay.textContent = newRole.charAt(0).toUpperCase() + newRole.slice(1)

      // Update styling
      const badge = roleDisplay.closest("span")
      if (badge) {
        badge.classList.remove("bg-blue-100", "text-blue-800", "bg-green-100", "text-green-800")
        if (newRole === "user") {
          badge.classList.add("bg-blue-100", "text-blue-800")
        } else {
          badge.classList.add("bg-green-100", "text-green-800")
        }
      }

      if (this.debugValue) {
        console.log("Toggled role", { from: currentRole, to: newRole })
      }
    }
  }

  // Move message up in the list
  moveUp(event) {
    event.preventDefault()

    const messageElement = event.currentTarget.closest("[data-message-index]")
    if (!messageElement) return

    const previousElement = messageElement.previousElementSibling
    if (previousElement && previousElement.hasAttribute("data-message-index")) {
      messageElement.parentNode.insertBefore(messageElement, previousElement)
      this.reindexMessages()

      if (this.debugValue) {
        console.log("Moved message up")
      }
    }
  }

  // Move message down in the list
  moveDown(event) {
    event.preventDefault()

    const messageElement = event.currentTarget.closest("[data-message-index]")
    if (!messageElement) return

    const nextElement = messageElement.nextElementSibling
    if (nextElement && nextElement.hasAttribute("data-message-index")) {
      messageElement.parentNode.insertBefore(nextElement, messageElement)
      this.reindexMessages()

      if (this.debugValue) {
        console.log("Moved message down")
      }
    }
  }

  // Duplicate a message
  duplicateMessage(event) {
    event.preventDefault()

    if (this.messageIndex >= this.maxMessagesValue) {
      this.showNotification("Maximum number of messages reached", "warning")
      return
    }

    const messageElement = event.currentTarget.closest("[data-message-index]")
    if (!messageElement) return

    const roleInput = messageElement.querySelector("input[type='hidden']")
    const textarea = messageElement.querySelector("textarea")

    if (roleInput && textarea) {
      const newMessage = this.createMessageElement(
        this.messageIndex,
        roleInput.value,
        textarea.value
      )

      messageElement.after(newMessage)
      this.messageIndex++
      this.reindexMessages()
      this.updateMessageCount()

      if (this.debugValue) {
        console.log("Duplicated message")
      }
    }
  }

  // Reset messages to original values
  reset(event) {
    event.preventDefault()

    // This would require storing original values - for now just confirm
    if (confirm("Reset all messages to original values? This cannot be undone.")) {
      window.location.reload()
    }
  }

  // Private methods

  createMessageElement(index, role, content) {
    const div = document.createElement("div")
    div.className = "bg-gray-50 rounded-lg p-4 border border-gray-200"
    div.setAttribute("data-message-index", index)

    const roleClass = role === "user" ? "bg-blue-100 text-blue-800" : "bg-green-100 text-green-800"

    div.innerHTML = `
      <div class="flex items-center justify-between mb-2">
        <div class="flex items-center gap-2">
          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${roleClass}">
            <span data-role-display>${role.charAt(0).toUpperCase() + role.slice(1)}</span>
          </span>
          <button type="button"
                  class="text-xs text-gray-500 hover:text-gray-700"
                  data-action="click->prompt-editor#toggleRole">
            Toggle Role
          </button>
        </div>
        <div class="flex items-center gap-1">
          <button type="button"
                  class="p-1 text-gray-400 hover:text-gray-600"
                  title="Move up"
                  data-action="click->prompt-editor#moveUp">
            <i class="bi bi-chevron-up"></i>
          </button>
          <button type="button"
                  class="p-1 text-gray-400 hover:text-gray-600"
                  title="Move down"
                  data-action="click->prompt-editor#moveDown">
            <i class="bi bi-chevron-down"></i>
          </button>
          <button type="button"
                  class="p-1 text-gray-400 hover:text-gray-600"
                  title="Duplicate"
                  data-action="click->prompt-editor#duplicateMessage">
            <i class="bi bi-copy"></i>
          </button>
          <button type="button"
                  class="p-1 text-gray-400 hover:text-red-600"
                  title="Remove"
                  data-action="click->prompt-editor#removeMessage">
            <i class="bi bi-trash"></i>
          </button>
        </div>
      </div>
      <input type="hidden" name="messages[${index}][role]" value="${role}">
      <textarea
        name="messages[${index}][content]"
        rows="3"
        class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm font-mono focus:ring-blue-500 focus:border-blue-500"
        placeholder="Enter message content..."
      >${this.escapeHtml(content)}</textarea>
    `

    return div
  }

  countMessages() {
    if (!this.hasMessagesContainerTarget) return 0
    return this.messagesContainerTarget.querySelectorAll("[data-message-index]").length
  }

  reindexMessages() {
    if (!this.hasMessagesContainerTarget) return

    const messages = this.messagesContainerTarget.querySelectorAll("[data-message-index]")
    messages.forEach((message, index) => {
      message.setAttribute("data-message-index", index)

      const roleInput = message.querySelector("input[type='hidden']")
      const textarea = message.querySelector("textarea")

      if (roleInput) {
        roleInput.name = `messages[${index}][role]`
      }
      if (textarea) {
        textarea.name = `messages[${index}][content]`
      }
    })

    this.messageIndex = messages.length
  }

  updateMessageCount() {
    if (this.hasMessageCountTarget) {
      this.messageCountTarget.textContent = this.countMessages()
    }
  }

  showNotification(message, type = "info") {
    // Simple notification - could be enhanced with a toast system
    const colors = {
      info: "bg-blue-100 text-blue-800",
      warning: "bg-yellow-100 text-yellow-800",
      error: "bg-red-100 text-red-800",
      success: "bg-green-100 text-green-800"
    }

    const notification = document.createElement("div")
    notification.className = `fixed top-4 right-4 px-4 py-2 rounded-lg ${colors[type]} z-50 transition-opacity duration-300`
    notification.textContent = message
    document.body.appendChild(notification)

    setTimeout(() => {
      notification.style.opacity = "0"
      setTimeout(() => notification.remove(), 300)
    }, 3000)
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  disconnect() {
    if (this.debugValue) {
      console.log("Prompt editor controller disconnected")
    }
  }
}
