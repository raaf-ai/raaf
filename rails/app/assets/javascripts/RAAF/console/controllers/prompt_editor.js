// Prompt editor — add and remove user messages on the replay form.
//
// The replay form reads the messages straight out of the DOM, so a row added
// here only has to carry the same shape as one rendered by the server: a role,
// a textarea, and an index.
class PromptEditorController extends Controller {
  static targets = ["messages", "empty"]

  addMessage(event) {
    event.preventDefault()
    if (!this.hasMessagesTarget) return

    const index = this.rows().length
    const row = document.createElement("div")
    row.className = "raaf-msg"
    row.dataset.messageIndex = index
    row.innerHTML =
      '<div class="raaf-msg-head">' +
        '<span class="raaf-msg-role">user</span>' +
        '<button type="button" class="raaf-msg-remove" aria-label="Remove message" ' +
          'data-action="click->prompt-editor#removeMessage"><i class="bi bi-x-lg"></i></button>' +
      '</div>' +
      '<textarea rows="4" name="user_messages[' + index + '][content]" ' +
        'class="raaf-input raaf-input--glass raaf-textarea raaf-input--mono"></textarea>' +
      '<input type="hidden" name="user_messages[' + index + '][role]" value="user">'

    this.messagesTarget.appendChild(row)
    this.toggleEmpty()
    row.querySelector("textarea").focus()
  }

  removeMessage(event) {
    event.preventDefault()
    const row = event.currentTarget.closest("[data-message-index]")
    if (row) row.remove()
    this.reindex()
    this.toggleEmpty()
  }

  // Field names carry the index, so removing the first of three messages would
  // otherwise post 1 and 2 with no 0 between them.
  reindex() {
    this.rows().forEach((row, index) => {
      row.dataset.messageIndex = index
      const body = row.querySelector("textarea")
      const role = row.querySelector("input[type='hidden']")
      if (body) body.name = "user_messages[" + index + "][content]"
      if (role) role.name = "user_messages[" + index + "][role]"
    })
  }

  toggleEmpty() {
    if (!this.hasEmptyTarget) return

    this.emptyTarget.classList.toggle("hidden", this.rows().length > 0)
  }

  rows() {
    if (!this.hasMessagesTarget) return []

    return Array.from(this.messagesTarget.querySelectorAll("[data-message-index]"))
  }
}
