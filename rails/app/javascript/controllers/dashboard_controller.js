// RAAF Dashboard Stimulus Controller with ActionCable Integration
// Combines real-time WebSocket updates with polling fallback
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = [
    "connectionStatus",
    "tracesContainer",
    "lastUpdated",
    "refreshButton",
    "autoRefreshToggle",
    "totalTraces",
    "activeTraces",
    "errorRate",
    "avgDuration",
    "tracesChart",
    "errorTrends",
    "topWorkflows",
    "alertsContainer"
  ]

  static values = {
    channelName: { type: String, default: "RubyAIAgentsFactory::Tracing::TracesChannel" },
    pollingInterval: { type: Number, default: 5000 },
    autoRefresh: { type: Boolean, default: true },
    maxReconnectAttempts: { type: Number, default: 10 },
    reconnectDelay: { type: Number, default: 1000 }
  }

  connect() {
    console.log("🚀 RAAF Dashboard Controller connected successfully!")

    // Initialize connection state
    this.consumer = null
    this.subscription = null
    this.isConnected = false
    this.reconnectAttempts = 0
    this.pollingIntervalId = null
    this.autoRefreshIntervalId = null

    this.initialize()
  }

  disconnect() {
    console.log("🔌 RAAF Dashboard Controller disconnecting...")
    this.destroy()
  }

  initialize() {
    // Try ActionCable first, fallback to polling
    if (typeof createConsumer !== 'undefined') {
      this.setupActionCable()
    } else {
      console.warn("ActionCable not available, using polling fallback")
      this.setupPolling()
    }

    this.setupEventHandlers()
    this.updateConnectionStatus()

    // Start auto-refresh if enabled
    if (this.autoRefreshValue) {
      this.startAutoRefresh()
    }
  }

  setupActionCable() {
    try {
      console.log(`🔗 Setting up ActionCable connection to ${this.channelNameValue}`)
      this.consumer = createConsumer()

      this.subscription = this.consumer.subscriptions.create(this.channelNameValue, {
        connected: () => {
          console.log("✅ Connected to TracesChannel")
          this.isConnected = true
          this.reconnectAttempts = 0
          this.updateConnectionStatus('connected')

          // Stop polling when WebSocket is connected
          this.stopPolling()
        },

        disconnected: () => {
          console.log("❌ Disconnected from TracesChannel")
          this.isConnected = false
          this.updateConnectionStatus('disconnected')
          this.attemptReconnect()
        },

        received: (data) => {
          console.log("📨 Received data:", data)
          this.handleReceived(data)
        },

        rejected: () => {
          console.error("🚫 Subscription rejected")
          this.setupPolling()
        }
      })
    } catch (error) {
      console.error("❌ ActionCable setup failed:", error)
      this.setupPolling()
    }
  }

  setupPolling() {
    console.log("📊 Setting up polling fallback")
    this.stopPolling() // Clear any existing polling

    this.pollingIntervalId = setInterval(() => {
      this.fetchUpdates()
    }, this.pollingIntervalValue)

    this.updateConnectionStatus('polling')
  }

  stopPolling() {
    if (this.pollingIntervalId) {
      clearInterval(this.pollingIntervalId)
      this.pollingIntervalId = null
    }
  }

  setupEventHandlers() {
    // Refresh button
    if (this.hasRefreshButtonTarget) {
      this.refreshButtonTarget.addEventListener('click', (e) => {
        e.preventDefault()
        this.requestPerformanceUpdate()
      })
    }

    // Auto-refresh toggle
    if (this.hasAutoRefreshToggleTarget) {
      this.autoRefreshToggleTarget.addEventListener('change', (e) => {
        this.autoRefreshValue = e.target.checked
        if (this.autoRefreshValue) {
          this.startAutoRefresh()
        } else {
          this.stopAutoRefresh()
        }
      })
    }

    // Trace row click handlers for details
    this.element.addEventListener('click', (e) => {
      const traceRow = e.target.closest('.trace-row[data-trace-id]')
      if (traceRow) {
        const traceId = traceRow.dataset.traceId
        this.requestTraceDetails(traceId)
      }
    })
  }

  handleReceived(data) {
    switch (data.type) {
      case 'initial_data':
        this.updateTracesList(data.traces)
        this.updateDashboardStats(data.stats)
        break

      case 'trace_update':
        this.updateSingleTrace(data.trace)
        break

      case 'new_trace':
        this.addNewTrace(data.trace)
        break

      case 'trace_details':
        this.showTraceDetails(data.trace)
        break

      case 'performance_update':
        this.updateDashboardStats(data.stats)
        this.updatePerformanceMetrics(data.metrics)
        break

      case 'alert':
        this.showAlert(data.alert)
        break

      default:
        console.log('❓ Unknown message type:', data.type)
    }
  }

  updateTracesList(traces) {
    if (!this.hasTracesContainerTarget) return

    const tracesHTML = traces.map(trace => this.renderTraceRow(trace)).join('')
    this.tracesContainerTarget.innerHTML = tracesHTML

    this.updateLastUpdated()
  }

  renderTraceRow(trace) {
    const statusBadge = this.getStatusBadge(trace.status)
    const duration = trace.duration_ms ? `${trace.duration_ms}ms` : 'Running...'
    const errorBadge = trace.error_count > 0 ?
      `<span class="badge badge-danger">${trace.error_count} errors</span>` : ''

    return `
      <tr class="trace-row" data-trace-id="${trace.trace_id}">
        <td>
          <span class="trace-id" title="${trace.trace_id}">
            ${trace.trace_id.substring(0, 8)}...
          </span>
        </td>
        <td>
          <strong>${trace.workflow_name}</strong>
        </td>
        <td>${statusBadge}</td>
        <td>
          <span class="duration">${duration}</span>
        </td>
        <td>
          <span class="span-count">${trace.span_count} spans</span>
          ${errorBadge}
        </td>
        <td>
          <small class="text-muted">
            ${this.formatTimeAgo(trace.started_at)}
          </small>
        </td>
      </tr>
    `
  }

  getStatusBadge(status) {
    const badges = {
      'running': '<span class="badge badge-primary">Running</span>',
      'completed': '<span class="badge badge-success">Completed</span>',
      'failed': '<span class="badge badge-danger">Failed</span>',
      'cancelled': '<span class="badge badge-secondary">Cancelled</span>'
    }
    return badges[status] || `<span class="badge badge-light">${status}</span>`
  }

  updateSingleTrace(trace) {
    const existingRow = this.element.querySelector(`[data-trace-id="${trace.trace_id}"]`)
    if (existingRow) {
      existingRow.outerHTML = this.renderTraceRow(trace)
    }
  }

  addNewTrace(trace) {
    if (!this.hasTracesContainerTarget) return

    const newRow = this.renderTraceRow(trace)
    this.tracesContainerTarget.insertAdjacentHTML('afterbegin', newRow)

    // Remove oldest traces if we have too many
    const rows = this.tracesContainerTarget.querySelectorAll('tr')
    if (rows.length > 50) {
      rows[rows.length - 1].remove()
    }

    // Highlight new trace
    const newRowElement = this.tracesContainerTarget.querySelector('tr:first-child')
    if (newRowElement) {
      newRowElement.classList.add('highlight-new')
      setTimeout(() => {
        newRowElement.classList.remove('highlight-new')
      }, 2000)
    }
  }

  updateDashboardStats(stats) {
    this.updateStat('totalTracesTarget', stats.total_traces)
    this.updateStat('activeTracesTarget', stats.active_traces)
    this.updateStat('errorRateTarget', `${stats.error_rate}%`)
    this.updateStat('avgDurationTarget', `${stats.avg_duration}ms`)
  }

  updateStat(targetName, value) {
    if (this[`has${targetName.charAt(0).toUpperCase() + targetName.slice(1)}`]) {
      const element = this[targetName]
      const oldValue = element.textContent
      element.textContent = value

      // Animate change
      if (oldValue !== value) {
        element.classList.add('stat-updated')
        setTimeout(() => {
          element.classList.remove('stat-updated')
        }, 1000)
      }
    }
  }

  updatePerformanceMetrics(metrics) {
    if (metrics.traces_per_hour && this.hasTracesChartTarget) {
      this.updateTracesChart(metrics.traces_per_hour)
    }

    if (metrics.error_trends && this.hasErrorTrendsTarget) {
      this.updateErrorTrendsChart(metrics.error_trends)
    }

    if (metrics.duration_percentiles) {
      this.updatePercentileDisplay(metrics.duration_percentiles)
    }

    if (metrics.top_workflows && this.hasTopWorkflowsTarget) {
      this.updateTopWorkflows(metrics.top_workflows)
    }
  }

  updateTracesChart(data) {
    if (!this.hasTracesChartTarget) return

    // Simple ASCII-style bar chart
    const maxCount = Math.max(...data.map(d => d.count))
    const chartHTML = data.map(point => {
      const barHeight = maxCount > 0 ? (point.count / maxCount) * 100 : 0
      return `
        <div class="chart-bar" style="height: ${barHeight}%" title="${point.hour}: ${point.count} traces">
          <div class="bar-fill"></div>
          <span class="bar-label">${point.hour}</span>
        </div>
      `
    }).join('')

    this.tracesChartTarget.innerHTML = `<div class="simple-chart">${chartHTML}</div>`
  }

  updateErrorTrendsChart(trends) {
    if (!this.hasErrorTrendsTarget) return

    const trendsHTML = trends.slice(-7).map(day => `
      <div class="trend-day">
        <div class="trend-date">${day.date}</div>
        <div class="trend-stats">
          <span class="total-traces">${day.total} traces</span>
          <span class="error-rate ${day.error_rate > 5 ? 'high-error' : ''}">${day.error_rate}% errors</span>
        </div>
      </div>
    `).join('')

    this.errorTrendsTarget.innerHTML = trendsHTML
  }

  updatePercentileDisplay(percentiles) {
    Object.entries(percentiles).forEach(([percentile, value]) => {
      const element = this.element.querySelector(`#${percentile}-duration`)
      if (element) {
        element.textContent = `${value}ms`
      }
    })
  }

  updateTopWorkflows(workflows) {
    if (!this.hasTopWorkflowsTarget) return

    const workflowsHTML = workflows.map(workflow => {
      const total = workflow.completed + workflow.failed + workflow.running
      const successRate = total > 0 ? ((workflow.completed / total) * 100).toFixed(1) : 0

      return `
        <div class="workflow-item">
          <div class="workflow-name">${workflow.workflow_name}</div>
          <div class="workflow-stats">
            <span class="total">${total} total</span>
            <span class="success-rate ${successRate < 90 ? 'low-success' : ''}">${successRate}% success</span>
          </div>
        </div>
      `
    }).join('')

    this.topWorkflowsTarget.innerHTML = workflowsHTML
  }

  showTraceDetails(trace) {
    // Create modal or sidebar with detailed trace information
    const modal = this.createTraceModal(trace)
    document.body.appendChild(modal)

    // Show modal
    setTimeout(() => modal.classList.add('show'), 10)
  }

  createTraceModal(trace) {
    const modal = document.createElement('div')
    modal.className = 'trace-modal-overlay'
    modal.innerHTML = `
      <div class="trace-modal">
        <div class="trace-modal-header">
          <h3>Trace Details: ${trace.workflow_name}</h3>
          <button class="close-modal">&times;</button>
        </div>
        <div class="trace-modal-body">
          <div class="trace-info">
            <p><strong>Trace ID:</strong> ${trace.trace_id}</p>
            <p><strong>Status:</strong> ${this.getStatusBadge(trace.status)}</p>
            <p><strong>Duration:</strong> ${trace.duration_ms || 'N/A'}ms</p>
            <p><strong>Started:</strong> ${new Date(trace.started_at).toLocaleString()}</p>
            ${trace.ended_at ? `<p><strong>Ended:</strong> ${new Date(trace.ended_at).toLocaleString()}</p>` : ''}
          </div>
          <div class="spans-timeline">
            <h4>Spans (${trace.spans.length})</h4>
            ${this.renderSpansTimeline(trace.spans)}
          </div>
        </div>
      </div>
    `

    // Close modal handlers
    const closeButton = modal.querySelector('.close-modal')
    closeButton.addEventListener('click', () => {
      modal.classList.remove('show')
      setTimeout(() => modal.remove(), 300)
    })

    modal.addEventListener('click', (e) => {
      if (e.target === modal) {
        modal.classList.remove('show')
        setTimeout(() => modal.remove(), 300)
      }
    })

    return modal
  }

  renderSpansTimeline(spans) {
    return spans.map(span => `
      <div class="span-item ${span.status}">
        <div class="span-header">
          <span class="span-name">${span.name}</span>
          <span class="span-kind">${span.kind}</span>
          <span class="span-duration">${span.duration_ms || 'N/A'}ms</span>
        </div>
        ${span.attributes && Object.keys(span.attributes).length > 0 ? `
          <div class="span-attributes">
            ${Object.entries(span.attributes).map(([key, value]) =>
              `<span class="attribute">${key}: ${JSON.stringify(value)}</span>`
            ).join('')}
          </div>
        ` : ''}
      </div>
    `).join('')
  }

  showAlert(alert) {
    let alertsContainer = this.hasAlertsContainerTarget ?
      this.alertsContainerTarget : this.createAlertsContainer()

    const alertElement = document.createElement('div')
    alertElement.className = `alert alert-${alert.severity} alert-dismissible`
    alertElement.innerHTML = `
      <strong>${alert.title}</strong> ${alert.message}
      <button type="button" class="close" data-dismiss="alert">
        <span>&times;</span>
      </button>
    `

    alertsContainer.appendChild(alertElement)

    // Auto-dismiss
    const timeout = alert.severity === 'warning' ? 10000 : 30000
    setTimeout(() => {
      if (alertElement.parentNode) {
        alertElement.remove()
      }
    }, timeout)
  }

  createAlertsContainer() {
    const container = document.createElement('div')
    container.className = 'alerts-container'
    document.body.appendChild(container)
    return container
  }

  // Action methods for ActionCable
  requestTraceDetails(traceId) {
    if (this.subscription) {
      this.subscription.perform('request_trace_details', { trace_id: traceId })
    }
  }

  requestPerformanceUpdate() {
    if (this.subscription) {
      this.subscription.perform('request_performance_update')
    } else {
      this.fetchUpdates()
    }
  }

  // Polling fallback methods
  async fetchUpdates() {
    try {
      const response = await fetch('/raaf/tracing/dashboard.json')
      const data = await response.json()

      this.updateDashboardStats(data.stats)
      if (data.traces) {
        this.updateTracesList(data.traces)
      }

      this.updateConnectionStatus('updated')
    } catch (error) {
      console.error('❌ Polling update failed:', error)
      this.updateConnectionStatus('error')
    }
  }

  startAutoRefresh() {
    this.stopAutoRefresh()
    this.autoRefreshIntervalId = setInterval(() => {
      this.requestPerformanceUpdate()
    }, 30000) // 30 seconds
  }

  stopAutoRefresh() {
    if (this.autoRefreshIntervalId) {
      clearInterval(this.autoRefreshIntervalId)
      this.autoRefreshIntervalId = null
    }
  }

  attemptReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttemptsValue) {
      console.error('🔄 Max reconnection attempts reached, switching to polling')
      this.setupPolling()
      return
    }

    this.reconnectAttempts++
    const delay = this.reconnectDelayValue * Math.pow(2, this.reconnectAttempts - 1)

    setTimeout(() => {
      console.log(`🔄 Reconnection attempt ${this.reconnectAttempts}`)
      this.setupActionCable()
    }, delay)
  }

  updateConnectionStatus(status = null) {
    if (!this.hasConnectionStatusTarget) return

    const statusElement = this.connectionStatusTarget

    if (status) {
      statusElement.classList.remove('hidden')

      switch (status) {
        case 'connected':
          statusElement.className = 'mb-4 p-4 bg-green-50 border border-green-200 rounded-lg'
          statusElement.querySelector('.status-text').textContent = 'Connected to real-time updates'
          setTimeout(() => statusElement.classList.add('hidden'), 3000)
          break

        case 'disconnected':
          statusElement.className = 'mb-4 p-4 bg-yellow-50 border border-yellow-200 rounded-lg'
          statusElement.querySelector('.status-text').textContent = 'Disconnected - attempting to reconnect...'
          break

        case 'polling':
          statusElement.className = 'mb-4 p-4 bg-blue-50 border border-blue-200 rounded-lg'
          statusElement.querySelector('.status-text').textContent = 'Using polling updates (every 5 seconds)'
          setTimeout(() => statusElement.classList.add('hidden'), 3000)
          break

        case 'updated':
          statusElement.className = 'mb-4 p-4 bg-green-50 border border-green-200 rounded-lg'
          statusElement.querySelector('.status-text').textContent = 'Updated!'
          setTimeout(() => statusElement.classList.add('hidden'), 1000)
          break

        case 'error':
          statusElement.className = 'mb-4 p-4 bg-red-50 border border-red-200 rounded-lg'
          statusElement.querySelector('.status-text').textContent = 'Connection error - retrying...'
          setTimeout(() => statusElement.classList.add('hidden'), 3000)
          break
      }
    } else {
      // Default status based on connection state
      statusElement.className = this.isConnected ? 'connected' : 'disconnected'
      const statusText = statusElement.querySelector('.status-text')
      if (statusText) {
        statusText.textContent = this.isConnected ? 'Connected' : 'Disconnected'
      }
    }
  }

  updateLastUpdated() {
    if (this.hasLastUpdatedTarget) {
      this.lastUpdatedTarget.textContent = new Date().toLocaleTimeString()
    }
  }

  formatTimeAgo(timestamp) {
    const now = new Date()
    const time = new Date(timestamp)
    const diffMs = now - time
    const diffMins = Math.floor(diffMs / 60000)
    const diffHours = Math.floor(diffMins / 60)
    const diffDays = Math.floor(diffHours / 24)

    if (diffDays > 0) return `${diffDays}d ago`
    if (diffHours > 0) return `${diffHours}h ago`
    if (diffMins > 0) return `${diffMins}m ago`
    return 'Just now'
  }

  destroy() {
    // Clean up all connections and intervals
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }

    if (this.consumer) {
      this.consumer.disconnect()
      this.consumer = null
    }

    this.stopPolling()
    this.stopAutoRefresh()

    console.log("🧹 RAAF Dashboard Controller cleaned up")
  }
}