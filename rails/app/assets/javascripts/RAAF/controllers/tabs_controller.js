// RAAF Tabs Stimulus Controller
// Handles tab switching for comparison views
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  static values = {
    activeTab: { type: String, default: "" },
    debug: { type: Boolean, default: false }
  }

  connect() {
    // Initialize with first tab if no active tab is set
    if (!this.activeTabValue && this.hasTabTarget) {
      const firstTab = this.tabTargets[0]
      if (firstTab) {
        this.activeTabValue = firstTab.dataset.tabId
      }
    }

    this.showActiveTab()

    if (this.debugValue) {
      console.log("Tabs controller connected", { activeTab: this.activeTabValue })
    }
  }

  // Select a tab
  select(event) {
    event.preventDefault()

    const tabId = event.currentTarget.dataset.tabId
    if (!tabId) return

    this.activeTabValue = tabId
    this.showActiveTab()

    if (this.debugValue) {
      console.log("Tab selected", { tabId })
    }
  }

  // Select tab by ID (for programmatic use)
  selectTab(tabId) {
    this.activeTabValue = tabId
    this.showActiveTab()
  }

  // Show next tab
  next(event) {
    if (event) event.preventDefault()

    const currentIndex = this.getCurrentTabIndex()
    const nextIndex = (currentIndex + 1) % this.tabTargets.length
    const nextTab = this.tabTargets[nextIndex]

    if (nextTab) {
      this.activeTabValue = nextTab.dataset.tabId
      this.showActiveTab()
    }
  }

  // Show previous tab
  previous(event) {
    if (event) event.preventDefault()

    const currentIndex = this.getCurrentTabIndex()
    const prevIndex = (currentIndex - 1 + this.tabTargets.length) % this.tabTargets.length
    const prevTab = this.tabTargets[prevIndex]

    if (prevTab) {
      this.activeTabValue = prevTab.dataset.tabId
      this.showActiveTab()
    }
  }

  // Private methods

  showActiveTab() {
    // Update tab button states
    this.tabTargets.forEach(tab => {
      const tabId = tab.dataset.tabId
      const isActive = tabId === this.activeTabValue

      // Update classes
      tab.classList.remove(
        "border-blue-500", "text-blue-600",
        "border-transparent", "text-gray-500", "hover:text-gray-700"
      )

      if (isActive) {
        tab.classList.add("border-blue-500", "text-blue-600")
        tab.setAttribute("aria-selected", "true")
      } else {
        tab.classList.add("border-transparent", "text-gray-500", "hover:text-gray-700")
        tab.setAttribute("aria-selected", "false")
      }
    })

    // Update panel visibility
    this.panelTargets.forEach(panel => {
      const panelId = panel.dataset.tabId
      const isActive = panelId === this.activeTabValue

      if (isActive) {
        panel.classList.remove("hidden")
        panel.setAttribute("aria-hidden", "false")
      } else {
        panel.classList.add("hidden")
        panel.setAttribute("aria-hidden", "true")
      }
    })
  }

  getCurrentTabIndex() {
    return this.tabTargets.findIndex(tab => tab.dataset.tabId === this.activeTabValue)
  }

  // Keyboard navigation
  handleKeydown(event) {
    switch (event.key) {
      case "ArrowLeft":
        this.previous(event)
        break
      case "ArrowRight":
        this.next(event)
        break
      case "Home":
        event.preventDefault()
        if (this.tabTargets[0]) {
          this.activeTabValue = this.tabTargets[0].dataset.tabId
          this.showActiveTab()
        }
        break
      case "End":
        event.preventDefault()
        const lastTab = this.tabTargets[this.tabTargets.length - 1]
        if (lastTab) {
          this.activeTabValue = lastTab.dataset.tabId
          this.showActiveTab()
        }
        break
    }
  }

  disconnect() {
    if (this.debugValue) {
      console.log("Tabs controller disconnected")
    }
  }
}
