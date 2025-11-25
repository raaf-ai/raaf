// Pass Rate Time-Series Chart Controller
// Displays pass rate trend over time using D3.js line chart
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    agent: String,
    period: { type: String, default: "daily" },
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
    // D3 is loaded from vendor/javascript/d3/d3.min.js
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
        agent: this.agentValue || "",
        period: this.periodValue
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

    // Get container dimensions
    const containerWidth = container.clientWidth
    const containerHeight = Math.max(300, Math.min(500, containerWidth * 0.5))

    const margin = { top: 20, right: 30, bottom: 50, left: 60 }
    const width = containerWidth - margin.left - margin.right
    const height = containerHeight - margin.top - margin.bottom

    // Create SVG
    const svg = d3.select(container)
      .append("svg")
      .attr("width", containerWidth)
      .attr("height", containerHeight)
      .attr("role", "img")
      .attr("aria-label", "Pass rate trend over time")
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    // Parse dates and prepare data
    const parseDate = d3.isoParse
    const processedData = data.map(d => ({
      date: parseDate(d.date),
      passRate: d.pass_rate,
      total: d.total,
      passed: d.passed,
      failed: d.failed
    }))

    // Scales
    const x = d3.scaleTime()
      .domain(d3.extent(processedData, d => d.date))
      .range([0, width])

    const y = d3.scaleLinear()
      .domain([0, 100])
      .range([height, 0])

    // Axes
    const xAxis = d3.axisBottom(x)
      .ticks(Math.min(7, processedData.length))
      .tickFormat(d3.timeFormat("%m/%d"))

    const yAxis = d3.axisLeft(y)
      .ticks(5)
      .tickFormat(d => `${d}%`)

    // Grid lines
    svg.append("g")
      .attr("class", "grid")
      .attr("opacity", 0.1)
      .call(d3.axisLeft(y)
        .ticks(5)
        .tickSize(-width)
        .tickFormat("")
      )

    // Area gradient
    const gradient = svg.append("defs")
      .append("linearGradient")
      .attr("id", "pass-rate-gradient")
      .attr("x1", "0%")
      .attr("y1", "0%")
      .attr("x2", "0%")
      .attr("y2", "100%")

    gradient.append("stop")
      .attr("offset", "0%")
      .attr("stop-color", "#10b981")
      .attr("stop-opacity", 0.3)

    gradient.append("stop")
      .attr("offset", "100%")
      .attr("stop-color", "#10b981")
      .attr("stop-opacity", 0)

    // Line generator
    const line = d3.line()
      .x(d => x(d.date))
      .y(d => y(d.passRate))
      .curve(d3.curveMonotoneX)

    // Area generator
    const area = d3.area()
      .x(d => x(d.date))
      .y0(height)
      .y1(d => y(d.passRate))
      .curve(d3.curveMonotoneX)

    // Draw area
    svg.append("path")
      .datum(processedData)
      .attr("class", "area")
      .attr("fill", "url(#pass-rate-gradient)")
      .attr("d", area)

    // Draw line
    const path = svg.append("path")
      .datum(processedData)
      .attr("class", "line")
      .attr("fill", "none")
      .attr("stroke", "#10b981")
      .attr("stroke-width", 2.5)
      .attr("d", line)

    // Animate line drawing
    const totalLength = path.node().getTotalLength()
    path
      .attr("stroke-dasharray", `${totalLength} ${totalLength}`)
      .attr("stroke-dashoffset", totalLength)
      .transition()
      .duration(1000)
      .ease(d3.easeLinear)
      .attr("stroke-dashoffset", 0)

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

    // Y-axis label
    svg.append("text")
      .attr("transform", "rotate(-90)")
      .attr("y", -margin.left + 15)
      .attr("x", -height / 2)
      .attr("text-anchor", "middle")
      .style("font-size", "12px")
      .style("fill", this.getThemeColor("text"))
      .text("Pass Rate (%)")

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

    // Data points with hover
    svg.selectAll(".dot")
      .data(processedData)
      .enter()
      .append("circle")
      .attr("class", "dot")
      .attr("cx", d => x(d.date))
      .attr("cy", d => y(d.passRate))
      .attr("r", 4)
      .attr("fill", "#10b981")
      .attr("stroke", "#fff")
      .attr("stroke-width", 2)
      .style("cursor", "pointer")
      .on("mouseover", (event, d) => {
        d3.select(event.currentTarget)
          .transition()
          .duration(200)
          .attr("r", 6)

        tooltip
          .style("visibility", "visible")
          .html(`
            <div style="font-weight: 600; margin-bottom: 4px;">
              ${d3.timeFormat("%B %d, %Y")(d.date)}
            </div>
            <div>Pass Rate: <strong>${d.passRate.toFixed(1)}%</strong></div>
            <div style="color: #10b981;">Passed: ${d.passed}</div>
            <div style="color: #ef4444;">Failed: ${d.failed}</div>
            <div style="margin-top: 4px; font-size: 11px; opacity: 0.8;">
              Total: ${d.total} evaluations
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
      .on("mouseout", (event) => {
        d3.select(event.currentTarget)
          .transition()
          .duration(200)
          .attr("r", 4)

        tooltip.style("visibility", "hidden")
      })

    // Apply theme-aware colors
    this.applyThemeColors(svg)
  }

  getThemeColor(colorType) {
    const isDark = document.documentElement.classList.contains('dark')

    const colors = {
      text: isDark ? "#e5e7eb" : "#374151",
      "tooltip-bg": isDark ? "#1f2937" : "#ffffff",
      "tooltip-text": isDark ? "#f3f4f6" : "#111827",
      "tooltip-border": isDark ? "#374151" : "#d1d5db"
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
