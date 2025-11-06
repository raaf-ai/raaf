// Monaco Editor Stimulus Controller
// Integrates Monaco Editor for code/prompt editing with validation and diff view

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editor", "content", "validation"]
  static values = {
    language: { type: String, default: "markdown" },
    readonly: { type: Boolean, default: false },
    originalContent: String
  }

  async connect() {
    await this.loadMonaco()
    this.initializeEditor()
    this.restoreFromSession()
  }

  disconnect() {
    if (this.editor) {
      this.editor.dispose()
    }
    this.stopPolling()
  }

  async loadMonaco() {
    if (window.monaco) return

    return new Promise((resolve, reject) => {
      const script = document.createElement('script')
      script.src = 'https://cdn.jsdelivr.net/npm/monaco-editor@0.44.0/min/vs/loader.js'
      script.onload = () => {
        require.config({ paths: { vs: 'https://cdn.jsdelivr.net/npm/monaco-editor@0.44.0/min/vs' } })
        require(['vs/editor/editor.main'], () => {
          this.defineCustomTheme()
          resolve()
        })
      }
      script.onerror = reject
      document.head.appendChild(script)
    })
  }

  defineCustomTheme() {
    monaco.editor.defineTheme('raaf-eval-dark', {
      base: 'vs-dark',
      inherit: true,
      rules: [
        { token: 'comment', foreground: '6A9955' },
        { token: 'keyword', foreground: '569CD6' },
        { token: 'string', foreground: 'CE9178' }
      ],
      colors: {
        'editor.background': '#1E1E1E',
        'editor.foreground': '#D4D4D4'
      }
    })
  }

  initializeEditor() {
    this.editor = monaco.editor.create(this.editorTarget, {
      value: this.contentTarget.value || '',
      language: this.languageValue,
      theme: 'raaf-eval-dark',
      readOnly: this.readonlyValue,
      minimap: { enabled: true },
      lineNumbers: 'on',
      automaticLayout: true,
      wordWrap: 'on',
      scrollBeyondLastLine: false,
      renderWhitespace: 'selection'
    })

    // Sync content back to form
    this.editor.onDidChangeModelContent(() => {
      this.contentTarget.value = this.editor.getValue()
      this.validateContent()
      this.saveToSession()
    })

    // Set up keyboard shortcuts
    this.setupKeyboardShortcuts()
  }

  setupKeyboardShortcuts() {
    // Cmd+S / Ctrl+S to save
    this.editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => {
      this.saveToSession()
      this.showNotification('Content saved to session')
    })

    // Cmd+Enter / Ctrl+Enter to submit form
    this.editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter, () => {
      const form = this.element.closest('form')
      if (form) form.requestSubmit()
    })
  }

  validateContent() {
    const content = this.editor.getValue()
    const errors = []

    // Basic validation
    if (content.length === 0) {
      errors.push({ message: 'Content cannot be empty', line: 0 })
    }

    if (content.length > 100000) {
      errors.push({ message: 'Content exceeds maximum length', line: 0 })
    }

    // Update validation indicator
    if (this.hasValidationTarget) {
      this.updateValidationUI(errors)
    }

    // Set Monaco markers for errors
    if (errors.length > 0) {
      const markers = errors.map(error => ({
        severity: monaco.MarkerSeverity.Error,
        startLineNumber: error.line || 1,
        startColumn: 1,
        endLineNumber: error.line || 1,
        endColumn: 100,
        message: error.message
      }))
      monaco.editor.setModelMarkers(this.editor.getModel(), 'validation', markers)
    } else {
      monaco.editor.setModelMarkers(this.editor.getModel(), 'validation', [])
    }

    return errors.length === 0
  }

  updateValidationUI(errors) {
    if (errors.length === 0) {
      this.validationTarget.innerHTML = `
        <span class="inline-block w-3 h-3 bg-green-500 rounded-full"></span>
        <span class="text-sm text-gray-700">Valid</span>
      `
    } else {
      this.validationTarget.innerHTML = `
        <span class="inline-block w-3 h-3 bg-red-500 rounded-full"></span>
        <span class="text-sm text-red-700">${errors.length} error(s)</span>
      `
    }
  }

  showDiff() {
    if (!this.hasOriginalContentValue) return

    const originalModel = monaco.editor.createModel(this.originalContentValue, this.languageValue)
    const modifiedModel = this.editor.getModel()

    const diffEditor = monaco.editor.createDiffEditor(this.editorTarget, {
      enableSplitViewResizing: true,
      renderSideBySide: true
    })

    diffEditor.setModel({
      original: originalModel,
      modified: modifiedModel
    })

    // Store reference to switch back
    this.diffEditor = diffEditor
    this.regularEditor = this.editor
    this.editor = diffEditor
  }

  toggleDiff() {
    if (this.diffEditor) {
      // Switch back to regular editor
      this.editor = this.regularEditor
      this.diffEditor.dispose()
      this.diffEditor = null
      this.initializeEditor()
    } else {
      this.showDiff()
    }
  }

  reset() {
    if (confirm('Reset to original content? This will discard all changes.')) {
      this.editor.setValue(this.originalContentValue || '')
      this.saveToSession()
    }
  }

  saveToSession() {
    const key = `raaf-eval-editor-${this.element.id}`
    sessionStorage.setItem(key, this.editor.getValue())
  }

  restoreFromSession() {
    const key = `raaf-eval-editor-${this.element.id}`
    const saved = sessionStorage.getItem(key)
    if (saved) {
      this.editor.setValue(saved)
    }
  }

  showNotification(message) {
    // Simple notification - could be enhanced with a toast library
    const notification = document.createElement('div')
    notification.className = 'fixed bottom-4 right-4 bg-green-600 text-white px-4 py-2 rounded-lg shadow-lg'
    notification.textContent = message
    document.body.appendChild(notification)

    setTimeout(() => {
      notification.remove()
    }, 2000)
  }
}
