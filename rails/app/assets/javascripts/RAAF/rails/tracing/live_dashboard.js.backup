// Real-time Dashboard with WebSocket Integration
class LiveDashboard {
  constructor() {
    this.consumer = null;
    this.subscription = null;
    this.isConnected = false;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 10;
    this.reconnectDelay = 1000;
    
    this.initialize();
  }

  initialize() {
    if (typeof ActionCable !== 'undefined') {
      this.setupActionCable();
    } else {
      // Fallback to polling if ActionCable not available
      this.setupPolling();
    }
    
    this.setupEventHandlers();
    this.updateConnectionStatus();
  }

  setupActionCable() {
    try {
      this.consumer = ActionCable.createConsumer();
      this.subscription = this.consumer.subscriptions.create("RubyAIAgentsFactory::Tracing::TracesChannel", {
        connected: () => {
          console.log("Connected to TracesChannel");
          this.isConnected = true;
          this.reconnectAttempts = 0;
          this.updateConnectionStatus();
        },

        disconnected: () => {
          console.log("Disconnected from TracesChannel");
          this.isConnected = false;
          this.updateConnectionStatus();
          this.attemptReconnect();
        },

        received: (data) => {
          this.handleReceived(data);
        }
      });
    } catch (error) {
      console.error("ActionCable setup failed:", error);
      this.setupPolling();
    }
  }

  setupPolling() {
    console.log("Using polling fallback");
    this.pollingInterval = setInterval(() => {
      this.fetchUpdates();
    }, 5000);
  }

  setupEventHandlers() {
    // Request trace details when clicked
    document.addEventListener('click', (e) => {
      if (e.target.matches('.trace-row[data-trace-id]')) {
        const traceId = e.target.dataset.traceId;
        this.requestTraceDetails(traceId);
      }
    });

    // Refresh button
    const refreshBtn = document.getElementById('refresh-dashboard');
    if (refreshBtn) {
      refreshBtn.addEventListener('click', () => {
        this.requestPerformanceUpdate();
      });
    }

    // Auto-refresh toggle
    const autoRefreshToggle = document.getElementById('auto-refresh-toggle');
    if (autoRefreshToggle) {
      autoRefreshToggle.addEventListener('change', (e) => {
        if (e.target.checked) {
          this.startAutoRefresh();
        } else {
          this.stopAutoRefresh();
        }
      });
    }
  }

  handleReceived(data) {
    switch (data.type) {
      case 'initial_data':
        this.updateTracesList(data.traces);
        this.updateDashboardStats(data.stats);
        break;
        
      case 'trace_update':
        this.updateSingleTrace(data.trace);
        break;
        
      case 'new_trace':
        this.addNewTrace(data.trace);
        break;
        
      case 'trace_details':
        this.showTraceDetails(data.trace);
        break;
        
      case 'performance_update':
        this.updateDashboardStats(data.stats);
        this.updatePerformanceMetrics(data.metrics);
        break;
        
      case 'alert':
        this.showAlert(data.alert);
        break;
        
      default:
        console.log('Unknown message type:', data.type);
    }
  }

  updateTracesList(traces) {
    const tracesContainer = document.getElementById('traces-list');
    if (!tracesContainer) return;

    const tracesHTML = traces.map(trace => this.renderTraceRow(trace)).join('');
    tracesContainer.innerHTML = tracesHTML;
    
    // Update timestamp
    const lastUpdated = document.getElementById('last-updated');
    if (lastUpdated) {
      lastUpdated.textContent = new Date().toLocaleTimeString();
    }
  }

  renderTraceRow(trace) {
    const statusBadge = this.getStatusBadge(trace.status);
    const duration = trace.duration_ms ? `${trace.duration_ms}ms` : 'Running...';
    const errorBadge = trace.error_count > 0 ? 
      `<span class="badge badge-danger">${trace.error_count} errors</span>` : '';

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
    `;
  }

  getStatusBadge(status) {
    const badges = {
      'running': '<span class="badge badge-primary">Running</span>',
      'completed': '<span class="badge badge-success">Completed</span>',
      'failed': '<span class="badge badge-danger">Failed</span>',
      'cancelled': '<span class="badge badge-secondary">Cancelled</span>'
    };
    return badges[status] || `<span class="badge badge-light">${status}</span>`;
  }

  updateSingleTrace(trace) {
    const existingRow = document.querySelector(`[data-trace-id="${trace.trace_id}"]`);
    if (existingRow) {
      existingRow.outerHTML = this.renderTraceRow(trace);
    }
  }

  addNewTrace(trace) {
    const tracesContainer = document.getElementById('traces-list');
    if (!tracesContainer) return;

    const newRow = this.renderTraceRow(trace);
    tracesContainer.insertAdjacentHTML('afterbegin', newRow);
    
    // Remove oldest traces if we have too many
    const rows = tracesContainer.querySelectorAll('tr');
    if (rows.length > 50) {
      rows[rows.length - 1].remove();
    }
    
    // Highlight new trace
    const newRowElement = tracesContainer.querySelector('tr:first-child');
    newRowElement.classList.add('highlight-new');
    setTimeout(() => {
      newRowElement.classList.remove('highlight-new');
    }, 2000);
  }

  updateDashboardStats(stats) {
    this.updateStat('total-traces', stats.total_traces);
    this.updateStat('active-traces', stats.active_traces);
    this.updateStat('error-rate', `${stats.error_rate}%`);
    this.updateStat('avg-duration', `${stats.avg_duration}ms`);
  }

  updateStat(elementId, value) {
    const element = document.getElementById(elementId);
    if (element) {
      const oldValue = element.textContent;
      element.textContent = value;
      
      // Animate change
      if (oldValue !== value) {
        element.classList.add('stat-updated');
        setTimeout(() => {
          element.classList.remove('stat-updated');
        }, 1000);
      }
    }
  }

  updatePerformanceMetrics(metrics) {
    if (metrics.traces_per_hour) {
      this.updateTracesChart(metrics.traces_per_hour);
    }
    
    if (metrics.error_trends) {
      this.updateErrorTrendsChart(metrics.error_trends);
    }
    
    if (metrics.duration_percentiles) {
      this.updatePercentileDisplay(metrics.duration_percentiles);
    }
    
    if (metrics.top_workflows) {
      this.updateTopWorkflows(metrics.top_workflows);
    }
  }

  updateTracesChart(data) {
    const canvas = document.getElementById('traces-per-hour-chart');
    if (!canvas) return;

    // Simple ASCII-style bar chart for now
    const maxCount = Math.max(...data.map(d => d.count));
    const chartHTML = data.map(point => {
      const barHeight = maxCount > 0 ? (point.count / maxCount) * 100 : 0;
      return `
        <div class="chart-bar" style="height: ${barHeight}%" title="${point.hour}: ${point.count} traces">
          <div class="bar-fill"></div>
          <span class="bar-label">${point.hour}</span>
        </div>
      `;
    }).join('');

    const chartContainer = document.getElementById('traces-chart-container');
    if (chartContainer) {
      chartContainer.innerHTML = `<div class="simple-chart">${chartHTML}</div>`;
    }
  }

  updateErrorTrendsChart(trends) {
    const container = document.getElementById('error-trends');
    if (!container) return;

    const trendsHTML = trends.slice(-7).map(day => `
      <div class="trend-day">
        <div class="trend-date">${day.date}</div>
        <div class="trend-stats">
          <span class="total-traces">${day.total} traces</span>
          <span class="error-rate ${day.error_rate > 5 ? 'high-error' : ''}">${day.error_rate}% errors</span>
        </div>
      </div>
    `).join('');

    container.innerHTML = trendsHTML;
  }

  updatePercentileDisplay(percentiles) {
    Object.entries(percentiles).forEach(([percentile, value]) => {
      const element = document.getElementById(`${percentile}-duration`);
      if (element) {
        element.textContent = `${value}ms`;
      }
    });
  }

  updateTopWorkflows(workflows) {
    const container = document.getElementById('top-workflows');
    if (!container) return;

    const workflowsHTML = workflows.map(workflow => {
      const total = workflow.completed + workflow.failed + workflow.running;
      const successRate = total > 0 ? ((workflow.completed / total) * 100).toFixed(1) : 0;
      
      return `
        <div class="workflow-item">
          <div class="workflow-name">${workflow.workflow_name}</div>
          <div class="workflow-stats">
            <span class="total">${total} total</span>
            <span class="success-rate ${successRate < 90 ? 'low-success' : ''}">${successRate}% success</span>
          </div>
        </div>
      `;
    }).join('');

    container.innerHTML = workflowsHTML;
  }

  showTraceDetails(trace) {
    // Create modal or sidebar with detailed trace information
    const modal = this.createTraceModal(trace);
    document.body.appendChild(modal);
    
    // Show modal
    setTimeout(() => modal.classList.add('show'), 10);
  }

  createTraceModal(trace) {
    const modal = document.createElement('div');
    modal.className = 'trace-modal-overlay';
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
    `;

    // Close modal handler
    modal.querySelector('.close-modal').addEventListener('click', () => {
      modal.classList.remove('show');
      setTimeout(() => modal.remove(), 300);
    });

    // Close on backdrop click
    modal.addEventListener('click', (e) => {
      if (e.target === modal) {
        modal.classList.remove('show');
        setTimeout(() => modal.remove(), 300);
      }
    });

    return modal;
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
    `).join('');
  }

  showAlert(alert) {
    const alertsContainer = document.getElementById('alerts-container') || this.createAlertsContainer();
    
    const alertElement = document.createElement('div');
    alertElement.className = `alert alert-${alert.severity} alert-dismissible`;
    alertElement.innerHTML = `
      <strong>${alert.title}</strong> ${alert.message}
      <button type="button" class="close" data-dismiss="alert">
        <span>&times;</span>
      </button>
    `;
    
    alertsContainer.appendChild(alertElement);
    
    // Auto-dismiss after 10 seconds for warnings, 30 seconds for errors
    const timeout = alert.severity === 'warning' ? 10000 : 30000;
    setTimeout(() => {
      if (alertElement.parentNode) {
        alertElement.remove();
      }
    }, timeout);
  }

  createAlertsContainer() {
    const container = document.createElement('div');
    container.id = 'alerts-container';
    container.className = 'alerts-container';
    document.body.appendChild(container);
    return container;
  }

  requestTraceDetails(traceId) {
    if (this.subscription) {
      this.subscription.perform('request_trace_details', { trace_id: traceId });
    }
  }

  requestPerformanceUpdate() {
    if (this.subscription) {
      this.subscription.perform('request_performance_update');
    } else {
      this.fetchUpdates();
    }
  }

  fetchUpdates() {
    // Fallback polling implementation
    fetch('/tracing/dashboard.json')
      .then(response => response.json())
      .then(data => {
        this.updateDashboardStats(data.stats);
        if (data.traces) {
          this.updateTracesList(data.traces);
        }
      })
      .catch(error => {
        console.error('Polling update failed:', error);
      });
  }

  startAutoRefresh() {
    this.stopAutoRefresh();
    this.autoRefreshInterval = setInterval(() => {
      this.requestPerformanceUpdate();
    }, 30000); // 30 seconds
  }

  stopAutoRefresh() {
    if (this.autoRefreshInterval) {
      clearInterval(this.autoRefreshInterval);
      this.autoRefreshInterval = null;
    }
  }

  attemptReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error('Max reconnection attempts reached');
      this.setupPolling();
      return;
    }

    this.reconnectAttempts++;
    const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1);
    
    setTimeout(() => {
      console.log(`Reconnection attempt ${this.reconnectAttempts}`);
      this.setupActionCable();
    }, delay);
  }

  updateConnectionStatus() {
    const statusElement = document.getElementById('connection-status');
    if (statusElement) {
      statusElement.className = this.isConnected ? 'connected' : 'disconnected';
      statusElement.textContent = this.isConnected ? 'Connected' : 'Disconnected';
    }
  }

  formatTimeAgo(timestamp) {
    const now = new Date();
    const time = new Date(timestamp);
    const diffMs = now - time;
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMins / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffDays > 0) return `${diffDays}d ago`;
    if (diffHours > 0) return `${diffHours}h ago`;
    if (diffMins > 0) return `${diffMins}m ago`;
    return 'Just now';
  }

  destroy() {
    if (this.subscription) {
      this.subscription.unsubscribe();
    }
    if (this.consumer) {
      this.consumer.disconnect();
    }
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval);
    }
    this.stopAutoRefresh();
  }
}

// Initialize dashboard when DOM is ready
document.addEventListener('DOMContentLoaded', function() {
  if (document.getElementById('tracing-dashboard')) {
    window.liveDashboard = new LiveDashboard();
  }
});

// Cleanup on page unload
window.addEventListener('beforeunload', function() {
  if (window.liveDashboard) {
    window.liveDashboard.destroy();
  }
});