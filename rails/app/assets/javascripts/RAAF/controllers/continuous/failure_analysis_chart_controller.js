// Failure Analysis Chart Controller
// Displays failure breakdown by evaluator using D3.js horizontal bar chart
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    agent: String,
    refreshInterval: { type: Number, default: 30000 }
  }

  static targets = ["chart", "loading", "error"]

  connect() {
    this.resizeObserver = null
    this.refreshTimer = null

    // Load D3 and initialize
    this.loadD3().then(() => {
      this.loadData()
      this.setupAutoRefresh()
      this.setupResponsive()
    }).catch(error => {
      this.showError("Failed to load D3.js library")
      console.error("D3 loading error:", error)
    })
  }

  disconnect() {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
    }
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }

  async loadD3() {
    if (!window.d3) {
      throw new Error("D3.js not loaded")
    }
    this.d3 = window.d3
  }

  setupAutoRefresh() {
    if (this.refreshIntervalValue > 0) {
      this.refreshTimer = setInterval(() => {
        this.loadData()
      }, this.refreshIntervalValue)
    }
  }

  setupResponsive() {
    this.resizeObserver = new ResizeObserver(() => {
      if (this.data) {
        this.renderChart(this.data)
      }
    })
    this.resizeObserver.observe(this.chartTarget)
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
      this.renderChart(data)
      this.hideLoading()
    } catch (error) {
      this.showError(`Failed to load data: ${error.message}`)
      console.error("Data loading error:", error)
    }
  }

  renderChart(data) {
    if (!data || data.length === 0) {
      this.chartTarget.innerHTML = '<div class="text-gray-500 text-center py-8">No failures to analyze</div>'
      return
    }

    const d3 = this.d3
    const container = this.chartTarget

    // Clear existing chart
    container.innerHTML = ""

    // Sort by count descending
    const sortedData = data.sort((a, b) => b.count - a.count)

    // Get container dimensions
    const containerWidth = container.clientWidth
    const barHeight = 40
    const containerHeight = Math.max(200, sortedData.length * barHeight + 80)

    const margin = { top: 20, right: 80, bottom: 40, left: 150 }
    const width = containerWidth - margin.left - margin.right
    const height = containerHeight - margin.top - margin.bottom

    // Create SVG
    const svg = d3.select(container)
      .append("svg")
      .attr("width", containerWidth)
      .attr("height", containerHeight)
      .attr("role", "img")
      .attr("aria-label", "Failure analysis by evaluator")
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    // Scales
    const x = d3.scaleLinear()
      .domain([0, d3.max(sortedData, d => d.count) || 1])
      .range([0, width])
      .nice()

    const y = d3.scaleBand()
      .domain(sortedData.map(d => d.evaluator))
      .range([0, height])
      .padding(0.2)

    // Color scale (shades of red)
    const colorScale = d3.scaleSequential()
      .domain([0, sortedData.length - 1])
      .interpolator(d3.interpolateReds)

    // Axes
    const xAxis = d3.axisBottom(x)
      .ticks(5)
      .tickFormat(d3.format("d"))

    const yAxis = d3.axisLeft(y)

    // Grid lines
    svg.append("g")
      .attr("class", "grid")
      .attr("opacity", 0.1)
      .call(d3.axisBottom(x)
        .ticks(5)
        .tickSize(height)
        .tickFormat("")
      )

    // Draw bars
    const bars = svg.selectAll(".bar")
      .data(sortedData)
      .enter()
      .append("rect")
      .attr("class", "bar")
      .attr("x", 0)
      .attr("y", d => y(d.evaluator))
      .attr("width", 0)
      .attr("height", y.bandwidth())
      .attr("fill", (d, i) => colorScale(i))
      .attr("rx", 4)
      .style("cursor", "pointer")

    // Animate bars
    bars
      .transition()
      .duration(800)
      .delay((d, i) => i * 100)
      .attr("width", d => x(d.count))

    // Add count labels on bars
    const labels = svg.selectAll(".bar-label")
      .data(sortedData)
      .enter()
      .append("text")
      .attr("class", "bar-label")
      .attr("x", d => x(d.count) + 5)
      .attr("y", d => y(d.evaluator) + y.bandwidth() / 2)
      .attr("dy", "0.35em")
      .style("font-size", "12px")
      .style("font-weight", "600")
      .style("fill", this.getThemeColor("text"))
      .style("opacity", 0)
      .text(d => `${d.count} (${d.percentage}%)`)

    // Animate labels
    labels
      .transition()
      .duration(800)
      .delay((d, i) => i * 100 + 400)
      .style("opacity", 1)

    // Draw axes
    svg.append("g")
      .attr("class", "x-axis")
      .attr("transform", `translate(0,${height})`)
      .call(xAxis)

    svg.append("g")
      .attr("class", "y-axis")
      .call(yAxis)

    // Axis label
    svg.append("text")
      .attr("x", width / 2)
      .attr("y", height + margin.bottom - 5)
      .attr("text-anchor", "middle")
      .style("font-size", "12px")
      .style("fill", this.getThemeColor("text"))
      .text("Failure Count")

    // Tooltip
    const tooltip = d3.select(container)
      .append("div")
      .attr("class", "d3-tooltip")
      .style("position", "absolute")
      .style("visibility", "hidden")
      .style("background-color", this.getThemeColor("tooltip-bg"))
      .style("color", this.getThemeColor("tooltip-text"))
      .style("border", `1px solid ${this.getThemeColor("tooltip-border")}`)
      .style("border-radius", "4px")
      .style("padding", "8px 12px")
      .style("font-size", "12px")
      .style("pointer-events", "none")
      .style("z-index", "1000")
      .style("box-shadow", "0 2px 4px rgba(0,0,0,0.1)")

    // Bar hover effects
    bars
      .on("mouseover", function(event, d) {
        d3.select(this)
          .transition()
          .duration(200)
          .attr("opacity", 0.8)
          .attr("stroke", "#374151")
          .attr("stroke-width", 2)

        const total = d3.sum(sortedData, item => item.count)

        tooltip
          .style("visibility", "visible")
          .html(`
            <div style="font-weight: 600; margin-bottom: 4px;">
              ${d.evaluator}
            </div>
            <div>Failures: <strong style="color: #ef4444;">${d.count}</strong></div>
            <div>Percentage: <strong>${d.percentage}%</strong></div>
            <div style="margin-top: 4px; font-size: 11px; opacity: 0.8;">
              Total failures: ${total}
            </div>
          `)
      })
      .on("mousemove", (event) => {
        const containerRect = container.getBoundingClientRect()
        const x = event.clientX - containerRect.left + 10
        const y = event.clientY - containerRect.top - 10

        tooltip
          .style("left", `${x}px`)
          .style("top", `${y}px`)
      })
      .on("mouseout", function() {
        d3.select(this)
          .transition()
          .duration(200)
          .attr("opacity", 1)
          .attr("stroke", "none")

        tooltip.style("visibility", "hidden")
      })

    // Apply theme colors
    this.applyThemeColors(svg)

    // Add summary
    this.renderSummary(container, sortedData)
  }

  renderSummary(container, data) {
    const total = d3.sum(data, d => d.count)
    const topFailure = data[0]

    const summaryDiv = this.d3.select(container)
      .append("div")
      .attr("class", "failure-summary")
      .style("margin-top", "16px")
      .style("padding", "12px")
      .style("background-color", this.getThemeColor("summary-bg"))
      .style("border-left", "4px solid #ef4444")
      .style("border-radius", "6px")
      .style("font-size", "13px")

    summaryDiv.append("div")
      .style("font-weight", "600")
      .style("margin-bottom", "8px")
      .style("color", this.getThemeColor("text"))
      .text("Failure Analysis Summary")

    summaryDiv.append("div")
      .style("margin-bottom", "4px")
      .style("color", this.getThemeColor("text"))
      .html(`Total failures: <strong style="color: #ef4444;">${total}</strong>`)

    summaryDiv.append("div")
      .style("margin-bottom", "4px")
      .style("color", this.getThemeColor("text"))
      .html(`Top failing evaluator: <strong>${topFailure.evaluator}</strong> (${topFailure.percentage}%)`)

    summaryDiv.append("div")
      .style("font-size", "11px")
      .style("opacity", "0.7")
      .style("margin-top", "8px")
      .style("color", this.getThemeColor("text"))
      .text(`Showing ${data.length} evaluator${data.length !== 1 ? 's' : ''} with failures`)
  }

  getThemeColor(colorType) {
    const isDark = document.documentElement.classList.contains('dark')

    const colors = {
      text: isDark ? "#e5e7eb" : "#374151",
      "tooltip-bg": isDark ? "#1f2937" : "#ffffff",
      "tooltip-text": isDark ? "#f3f4f6" : "#111827",
      "tooltip-border": isDark ? "#374151" : "#d1d5db",
      "summary-bg": isDark ? "#1f2937" : "#fef2f2"
    }

    return colors[colorType] || colors.text
  }

  applyThemeColors(svg) {
    const textColor = this.getThemeColor("text")

    svg.selectAll(".x-axis text, .y-axis text")
      .style("fill", textColor)

    svg.selectAll(".x-axis path, .y-axis path, .x-axis line, .y-axis line")
      .style("stroke", textColor)
      .style("opacity", 0.3)
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
      this.chartTarget.innerHTML = `
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
