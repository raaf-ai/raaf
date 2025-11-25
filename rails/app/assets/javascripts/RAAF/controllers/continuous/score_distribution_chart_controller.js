// Score Distribution Histogram Controller
// Displays score distribution across buckets using D3.js bar chart
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
      this.chartTarget.innerHTML = '<div class="text-gray-500 text-center py-8">No data available</div>'
      return
    }

    const d3 = this.d3
    const container = this.chartTarget

    // Clear existing chart
    container.innerHTML = ""

    // Calculate total and percentages
    const total = d3.sum(data, d => d.count)
    const processedData = data.map(d => ({
      ...d,
      percentage: total > 0 ? (d.count / total * 100) : 0
    }))

    // Get container dimensions
    const containerWidth = container.clientWidth
    const containerHeight = Math.max(300, Math.min(400, containerWidth * 0.4))

    const margin = { top: 20, right: 20, bottom: 60, left: 60 }
    const width = containerWidth - margin.left - margin.right
    const height = containerHeight - margin.top - margin.bottom

    // Create SVG
    const svg = d3.select(container)
      .append("svg")
      .attr("width", containerWidth)
      .attr("height", containerHeight)
      .attr("role", "img")
      .attr("aria-label", "Score distribution histogram")
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    // Scales
    const x = d3.scaleBand()
      .domain(processedData.map(d => d.range))
      .range([0, width])
      .padding(0.2)

    const y = d3.scaleLinear()
      .domain([0, d3.max(processedData, d => d.count) || 1])
      .range([height, 0])
      .nice()

    // Color scale (gradient from red to yellow to green)
    const colorScale = d3.scaleSequential()
      .domain([0, processedData.length - 1])
      .interpolator(d3.interpolateRdYlGn)

    // Axes
    const xAxis = d3.axisBottom(x)
      .tickFormat(d => d)

    const yAxis = d3.axisLeft(y)
      .ticks(5)
      .tickFormat(d3.format("d"))

    // Grid lines
    svg.append("g")
      .attr("class", "grid")
      .attr("opacity", 0.1)
      .call(d3.axisLeft(y)
        .ticks(5)
        .tickSize(-width)
        .tickFormat("")
      )

    // Draw bars
    const bars = svg.selectAll(".bar")
      .data(processedData)
      .enter()
      .append("rect")
      .attr("class", "bar")
      .attr("x", d => x(d.range))
      .attr("width", x.bandwidth())
      .attr("y", height)
      .attr("height", 0)
      .attr("fill", (d, i) => colorScale(i))
      .attr("rx", 4)
      .style("cursor", "pointer")

    // Animate bars
    bars
      .transition()
      .duration(800)
      .delay((d, i) => i * 50)
      .attr("y", d => y(d.count))
      .attr("height", d => height - y(d.count))

    // Draw axes
    svg.append("g")
      .attr("class", "x-axis")
      .attr("transform", `translate(0,${height})`)
      .call(xAxis)
      .selectAll("text")
      .style("text-anchor", "end")
      .attr("dx", "-.8em")
      .attr("dy", ".15em")
      .attr("transform", "rotate(-45)")

    svg.append("g")
      .attr("class", "y-axis")
      .call(yAxis)

    // Axis labels
    svg.append("text")
      .attr("x", width / 2)
      .attr("y", height + margin.bottom - 5)
      .attr("text-anchor", "middle")
      .style("font-size", "12px")
      .style("fill", this.getThemeColor("text"))
      .text("Score Range")

    svg.append("text")
      .attr("transform", "rotate(-90)")
      .attr("y", -margin.left + 15)
      .attr("x", -height / 2)
      .attr("text-anchor", "middle")
      .style("font-size", "12px")
      .style("fill", this.getThemeColor("text"))
      .text("Count")

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

        tooltip
          .style("visibility", "visible")
          .html(`
            <div style="font-weight: 600; margin-bottom: 4px;">
              Score Range: ${d.range}
            </div>
            <div>Count: <strong>${d.count}</strong></div>
            <div>Percentage: <strong>${d.percentage.toFixed(1)}%</strong></div>
            <div style="margin-top: 4px; font-size: 11px; opacity: 0.8;">
              Total: ${total} evaluations
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

    // Summary statistics
    const stats = this.calculateStats(processedData)
    this.renderStats(container, stats, total)

    // Apply theme colors
    this.applyThemeColors(svg)
  }

  calculateStats(data) {
    // Calculate weighted statistics
    const total = d3.sum(data, d => d.count)
    if (total === 0) return { mean: 0, median: 0, mode: "N/A" }

    // Calculate mean (weighted average)
    let sum = 0
    data.forEach(d => {
      const rangeParts = d.range.split("-")
      const midpoint = (parseFloat(rangeParts[0]) + parseFloat(rangeParts[1])) / 2
      sum += midpoint * d.count
    })
    const mean = sum / total

    // Find mode (bucket with highest count)
    const mode = data.reduce((max, d) => d.count > max.count ? d : max, data[0])

    // Estimate median bucket
    let cumulativeCount = 0
    let medianBucket = data[0]
    const halfTotal = total / 2

    for (const d of data) {
      cumulativeCount += d.count
      if (cumulativeCount >= halfTotal) {
        medianBucket = d
        break
      }
    }

    return {
      mean: mean,
      median: medianBucket.range,
      mode: mode.range
    }
  }

  renderStats(container, stats, total) {
    const statsDiv = d3.select(container)
      .append("div")
      .attr("class", "score-stats")
      .style("margin-top", "16px")
      .style("display", "flex")
      .style("justify-content", "space-around")
      .style("padding", "12px")
      .style("background-color", this.getThemeColor("stats-bg"))
      .style("border-radius", "6px")
      .style("font-size", "13px")

    const statItems = [
      { label: "Total", value: total },
      { label: "Mean Score", value: stats.mean.toFixed(3) },
      { label: "Median Range", value: stats.median },
      { label: "Mode Range", value: stats.mode }
    ]

    statItems.forEach(item => {
      const statItem = statsDiv.append("div")
        .style("text-align", "center")

      statItem.append("div")
        .style("font-size", "11px")
        .style("opacity", "0.7")
        .style("margin-bottom", "4px")
        .text(item.label)

      statItem.append("div")
        .style("font-weight", "600")
        .style("color", this.getThemeColor("text"))
        .text(item.value)
    })
  }

  getThemeColor(colorType) {
    const isDark = document.documentElement.classList.contains('dark')

    const colors = {
      text: isDark ? "#e5e7eb" : "#374151",
      "tooltip-bg": isDark ? "#1f2937" : "#ffffff",
      "tooltip-text": isDark ? "#f3f4f6" : "#111827",
      "tooltip-border": isDark ? "#374151" : "#d1d5db",
      "stats-bg": isDark ? "#1f2937" : "#f9fafb"
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
