// Model Comparison Table Controller
// Displays sortable table comparing performance across models
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    agent: String,
    refreshInterval: { type: Number, default: 30000 }
  }

  static targets = ["table", "loading", "error"]

  connect() {
    this.refreshTimer = null
    this.sortColumn = null
    this.sortDirection = "desc"

    this.loadData()
    this.setupAutoRefresh()
  }

  disconnect() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }

  setupAutoRefresh() {
    if (this.refreshIntervalValue > 0) {
      this.refreshTimer = setInterval(() => {
        this.loadData()
      }, this.refreshIntervalValue)
    }
  }

  async loadData() {
    if (!this.hasUrlValue) {
      this.showError("No data URL configured")
      return
    }

    this.showLoading()

    try {
      const params = new URLSearchParams({
        agent: this.agentValue || ""
      })

      const response = await fetch(`${this.urlValue}?${params}`)
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }

      const data = await response.json()
      this.data = data
      this.renderTable(data)
      this.hideLoading()
    } catch (error) {
      this.showError(`Failed to load data: ${error.message}`)
      console.error("Data loading error:", error)
    }
  }

  renderTable(data) {
    if (!data || data.length === 0) {
      this.tableTarget.innerHTML = '<div class="text-gray-500 text-center py-8">No model data available</div>'
      return
    }

    // Apply current sort if any
    const sortedData = this.sortColumn ? this.sortData(data, this.sortColumn, this.sortDirection) : data

    const isDark = document.documentElement.classList.contains('dark')
    const tableClass = isDark ? 'bg-gray-800 text-gray-100' : 'bg-white text-gray-900'
    const headerClass = isDark ? 'bg-gray-700 text-gray-200' : 'bg-gray-50 text-gray-700'
    const rowClass = isDark ? 'hover:bg-gray-700' : 'hover:bg-gray-50'
    const borderClass = isDark ? 'border-gray-700' : 'border-gray-200'

    const tableHTML = `
      <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
        <thead class="${headerClass}">
          <tr>
            ${this.renderHeaderCell('model', 'Model', 'text-left')}
            ${this.renderHeaderCell('total_evaluations', 'Total Evals', 'text-right')}
            ${this.renderHeaderCell('pass_rate', 'Pass Rate', 'text-right')}
            ${this.renderHeaderCell('avg_score', 'Avg Score', 'text-right')}
            ${this.renderHeaderCell('avg_latency_ms', 'Avg Latency', 'text-right')}
            ${this.renderHeaderCell('total_cost', 'Total Cost', 'text-right')}
          </tr>
        </thead>
        <tbody class="${tableClass} divide-y ${borderClass}">
          ${sortedData.map(row => this.renderRow(row, rowClass)).join('')}
        </tbody>
      </table>
    `

    this.tableTarget.innerHTML = tableHTML

    // Attach sort event listeners
    this.tableTarget.querySelectorAll('[data-sort-column]').forEach(header => {
      header.addEventListener('click', (e) => {
        const column = e.currentTarget.dataset.sortColumn
        this.sortBy(column)
      })
    })
  }

  renderHeaderCell(column, label, alignment) {
    const isSorted = this.sortColumn === column
    const sortIcon = isSorted ? (this.sortDirection === 'asc' ? '↑' : '↓') : '↕'
    const sortableClass = 'cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors'

    return `
      <th
        scope="col"
        class="px-6 py-3 ${alignment} text-xs font-medium uppercase tracking-wider ${sortableClass}"
        data-sort-column="${column}"
        title="Click to sort by ${label}"
      >
        <div class="flex items-center ${alignment === 'text-right' ? 'justify-end' : ''}">
          <span>${label}</span>
          <span class="ml-1 ${isSorted ? 'text-blue-600 dark:text-blue-400' : 'opacity-50'}">${sortIcon}</span>
        </div>
      </th>
    `
  }

  renderRow(row, rowClass) {
    return `
      <tr class="${rowClass} transition-colors">
        <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
          ${this.escapeHtml(row.model)}
        </td>
        <td class="px-6 py-4 whitespace-nowrap text-sm text-right">
          ${row.total_evaluations.toLocaleString()}
        </td>
        <td class="px-6 py-4 whitespace-nowrap text-sm text-right">
          ${this.renderPassRate(row.pass_rate)}
        </td>
        <td class="px-6 py-4 whitespace-nowrap text-sm text-right">
          ${row.avg_score !== null ? row.avg_score.toFixed(4) : 'N/A'}
        </td>
        <td class="px-6 py-4 whitespace-nowrap text-sm text-right">
          ${this.renderLatency(row.avg_latency_ms)}
        </td>
        <td class="px-6 py-4 whitespace-nowrap text-sm text-right">
          ${this.renderCost(row.total_cost)}
        </td>
      </tr>
    `
  }

  renderPassRate(passRate) {
    let colorClass = 'text-gray-900 dark:text-gray-100'
    if (passRate >= 90) {
      colorClass = 'text-green-600 dark:text-green-400 font-semibold'
    } else if (passRate >= 70) {
      colorClass = 'text-yellow-600 dark:text-yellow-400'
    } else {
      colorClass = 'text-red-600 dark:text-red-400 font-semibold'
    }

    return `<span class="${colorClass}">${passRate.toFixed(1)}%</span>`
  }

  renderLatency(latencyMs) {
    if (latencyMs === null || latencyMs === undefined) {
      return 'N/A'
    }

    let colorClass = 'text-gray-900 dark:text-gray-100'
    if (latencyMs < 1000) {
      colorClass = 'text-green-600 dark:text-green-400'
    } else if (latencyMs < 5000) {
      colorClass = 'text-yellow-600 dark:text-yellow-400'
    } else {
      colorClass = 'text-red-600 dark:text-red-400'
    }

    return `<span class="${colorClass}">${Math.round(latencyMs).toLocaleString()} ms</span>`
  }

  renderCost(cost) {
    if (cost === null || cost === undefined) {
      return 'N/A'
    }

    return `<span class="font-mono">$${cost.toFixed(4)}</span>`
  }

  sortBy(column) {
    if (this.sortColumn === column) {
      // Toggle direction if same column
      this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc'
    } else {
      // New column, default to descending
      this.sortColumn = column
      this.sortDirection = 'desc'
    }

    this.renderTable(this.data)
  }

  sortData(data, column, direction) {
    const sorted = [...data].sort((a, b) => {
      let aVal = a[column]
      let bVal = b[column]

      // Handle null/undefined
      if (aVal === null || aVal === undefined) return 1
      if (bVal === null || bVal === undefined) return -1

      // String comparison for model names
      if (column === 'model') {
        return direction === 'asc'
          ? aVal.localeCompare(bVal)
          : bVal.localeCompare(aVal)
      }

      // Numeric comparison for everything else
      return direction === 'asc'
        ? aVal - bVal
        : bVal - aVal
    })

    return sorted
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  showLoading() {
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove("hidden")
    }
    if (this.hasErrorTarget) {
      this.errorTarget.classList.add("hidden")
    }
  }

  hideLoading() {
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.add("hidden")
    }
  }

  showError(message) {
    this.hideLoading()
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove("hidden")
    } else {
      this.tableTarget.innerHTML = `
        <div class="text-red-500 text-center py-8">
          <p>${message}</p>
        </div>
      `
    }
  }

  refresh() {
    this.loadData()
  }
}
