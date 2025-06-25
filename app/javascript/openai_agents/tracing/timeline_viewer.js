// Interactive Timeline and Gantt Chart Viewer
class TimelineViewer {
  constructor(containerSelector, data, config = {}) {
    this.container = document.querySelector(containerSelector);
    this.data = data;
    this.config = {
      height: config.height || 600,
      margin: { top: 20, right: 20, bottom: 40, left: 150 },
      zoomLevel: config.zoomLevel || 1.0,
      showAttributes: config.showAttributes !== false,
      groupByKind: config.groupByKind !== false,
      highlightErrors: config.highlightErrors !== false,
      ...config
    };
    
    this.selectedSpan = null;
    this.zoomTransform = null;
    
    this.init();
  }

  init() {
    this.setupContainer();
    this.createScales();
    this.createVisualization();
    this.bindEvents();
  }

  setupContainer() {
    this.width = this.container.clientWidth - this.config.margin.left - this.config.margin.right;
    this.height = this.config.height - this.config.margin.top - this.config.margin.bottom;
    
    // Clear existing content
    this.container.innerHTML = '';
    
    // Create SVG
    this.svg = d3.select(this.container)
      .append('svg')
      .attr('width', this.width + this.config.margin.left + this.config.margin.right)
      .attr('height', this.height + this.config.margin.top + this.config.margin.bottom);
    
    // Create main group
    this.g = this.svg.append('g')
      .attr('transform', `translate(${this.config.margin.left},${this.config.margin.top})`);
    
    // Create zoom behavior
    this.zoom = d3.zoom()
      .scaleExtent([0.1, 10])
      .on('zoom', (event) => this.handleZoom(event));
    
    this.svg.call(this.zoom);
  }

  createScales() {
    const spans = this.data.items || [];
    
    // Time scale
    this.xScale = d3.scaleLinear()
      .domain([0, this.data.total_duration_ms || 1000])
      .range([0, this.width]);
    
    // Y scale for span positioning
    const maxDepth = Math.max(...spans.map(s => s.depth || 0), 0);
    const rowHeight = 25;
    
    this.yScale = d3.scaleBand()
      .domain(spans.map((_, i) => i))
      .range([0, (spans.length * rowHeight)])
      .padding(0.1);
    
    // Color scale for span types
    this.colorScale = d3.scaleOrdinal()
      .domain(['agent', 'llm', 'tool', 'function', 'handoff'])
      .range(['#007bff', '#28a745', '#17a2b8', '#ffc107', '#6f42c1']);
  }

  createVisualization() {
    this.createTimeAxis();
    this.createSpanBars();
    this.createTooltip();
  }

  createTimeAxis() {
    // Time axis
    this.xAxis = d3.axisBottom(this.xScale)
      .tickFormat(d => `${d}ms`);
    
    this.g.append('g')
      .attr('class', 'x-axis')
      .attr('transform', `translate(0, ${this.height})`)
      .call(this.xAxis);
    
    // Grid lines
    this.g.append('g')
      .attr('class', 'grid')
      .attr('transform', `translate(0, ${this.height})`)
      .call(d3.axisBottom(this.xScale)
        .tickSize(-this.height)
        .tickFormat('')
      );
  }

  createSpanBars() {
    const spans = this.data.items || [];
    
    // Create span groups
    this.spanGroups = this.g.selectAll('.span-group')
      .data(spans)
      .enter()
      .append('g')
      .attr('class', 'span-group')
      .attr('transform', (d, i) => `translate(0, ${this.yScale(i)})`);
    
    // Span bars
    this.spanGroups.append('rect')
      .attr('class', 'span-bar')
      .attr('x', d => this.xScale(d.start_offset_ms))
      .attr('width', d => Math.max(2, this.xScale(d.duration_ms)))
      .attr('height', this.yScale.bandwidth())
      .attr('fill', d => this.getSpanColor(d))
      .attr('stroke', d => d.status === 'error' ? '#dc3545' : 'none')
      .attr('stroke-width', d => d.status === 'error' ? 2 : 0)
      .style('cursor', 'pointer')
      .on('click', (event, d) => this.selectSpan(d))
      .on('mouseover', (event, d) => this.showTooltip(event, d))
      .on('mouseout', () => this.hideTooltip());
    
    // Span labels
    this.spanGroups.append('text')
      .attr('class', 'span-label')
      .attr('x', -5)
      .attr('y', this.yScale.bandwidth() / 2)
      .attr('dy', '0.35em')
      .attr('text-anchor', 'end')
      .style('font-size', '12px')
      .style('fill', '#495057')
      .text(d => this.truncateText(d.name, 20));
    
    // Duration labels
    this.spanGroups.append('text')
      .attr('class', 'duration-label')
      .attr('x', d => this.xScale(d.start_offset_ms) + Math.max(2, this.xScale(d.duration_ms)) + 5)
      .attr('y', this.yScale.bandwidth() / 2)
      .attr('dy', '0.35em')
      .style('font-size', '10px')
      .style('fill', '#6c757d')
      .text(d => `${d.duration_ms}ms`);
    
    // Error indicators
    this.spanGroups.filter(d => d.status === 'error')
      .append('circle')
      .attr('class', 'error-indicator')
      .attr('cx', d => this.xScale(d.start_offset_ms) - 8)
      .attr('cy', this.yScale.bandwidth() / 2)
      .attr('r', 4)
      .attr('fill', '#dc3545')
      .append('title')
      .text('Error occurred in this span');
  }

  createTooltip() {
    this.tooltip = d3.select('body')
      .append('div')
      .attr('class', 'timeline-tooltip')
      .style('opacity', 0)
      .style('position', 'absolute')
      .style('background', 'rgba(0, 0, 0, 0.8)')
      .style('color', 'white')
      .style('padding', '10px')
      .style('border-radius', '4px')
      .style('pointer-events', 'none')
      .style('font-size', '12px')
      .style('z-index', 1000);
  }

  getSpanColor(span) {
    if (span.status === 'error') {
      return '#dc3545';
    }
    return this.colorScale(span.kind) || '#6c757d';
  }

  selectSpan(span) {
    this.selectedSpan = span;
    
    // Highlight selected span
    this.spanGroups.selectAll('.span-bar')
      .attr('stroke', d => d.id === span.id ? '#000' : (d.status === 'error' ? '#dc3545' : 'none'))
      .attr('stroke-width', d => d.id === span.id ? 3 : (d.status === 'error' ? 2 : 0));
    
    // Show span details
    this.showSpanDetails(span);
  }

  showSpanDetails(span) {
    const detailsPanel = document.getElementById('span-details-panel');
    const detailsContent = document.getElementById('span-details-content');
    
    const attributesHtml = span.attributes && Object.keys(span.attributes).length > 0 ?
      Object.entries(span.attributes).map(([key, value]) => 
        `<div class="attribute-item"><strong>${key}:</strong> ${this.formatAttributeValue(value)}</div>`
      ).join('') :
      '<div class="text-muted">No attributes available</div>';
    
    const errorDetailsHtml = span.error_details ?
      `<div class="error-details">
        <h5>Error Details</h5>
        <div><strong>Type:</strong> ${span.error_details.error_type}</div>
        <div><strong>Message:</strong> ${span.error_details.error_message}</div>
        ${span.error_details.error_stack ? 
          `<div><strong>Stack:</strong><pre>${span.error_details.error_stack.join('\n')}</pre></div>` : 
          ''}
      </div>` : '';
    
    detailsContent.innerHTML = `
      <div class="span-overview">
        <h4>${span.name}</h4>
        <div class="span-meta">
          <span class="badge badge-primary">${span.kind}</span>
          <span class="badge badge-${span.status === 'ok' ? 'success' : (span.status === 'error' ? 'danger' : 'warning')}">${span.status}</span>
        </div>
      </div>
      
      <div class="span-timing">
        <div><strong>Duration:</strong> ${span.duration_ms}ms</div>
        <div><strong>Start Time:</strong> ${span.start_time}</div>
        ${span.end_time ? `<div><strong>End Time:</strong> ${span.end_time}</div>` : ''}
        <div><strong>Depth:</strong> ${span.depth}</div>
      </div>
      
      ${errorDetailsHtml}
      
      <div class="span-attributes">
        <h5>Attributes</h5>
        ${attributesHtml}
      </div>
    `;
    
    detailsPanel.style.display = 'block';
  }

  formatAttributeValue(value) {
    if (typeof value === 'object') {
      return `<pre>${JSON.stringify(value, null, 2)}</pre>`;
    }
    return String(value);
  }

  showTooltip(event, span) {
    const tooltipContent = `
      <strong>${span.name}</strong><br/>
      Kind: ${span.kind}<br/>
      Status: ${span.status}<br/>
      Duration: ${span.duration_ms}ms<br/>
      Start: +${span.start_offset_ms}ms
    `;
    
    this.tooltip
      .html(tooltipContent)
      .style('left', (event.pageX + 10) + 'px')
      .style('top', (event.pageY - 10) + 'px')
      .style('opacity', 1);
  }

  hideTooltip() {
    this.tooltip.style('opacity', 0);
  }

  handleZoom(event) {
    this.zoomTransform = event.transform;
    
    // Update x scale
    const newXScale = this.zoomTransform.rescaleX(this.xScale);
    
    // Update axis
    this.g.select('.x-axis').call(d3.axisBottom(newXScale).tickFormat(d => `${d}ms`));
    this.g.select('.grid').call(d3.axisBottom(newXScale).tickSize(-this.height).tickFormat(''));
    
    // Update span positions and widths
    this.spanGroups.selectAll('.span-bar')
      .attr('x', d => newXScale(d.start_offset_ms))
      .attr('width', d => Math.max(1, newXScale(d.start_offset_ms + d.duration_ms) - newXScale(d.start_offset_ms)));
    
    this.spanGroups.selectAll('.duration-label')
      .attr('x', d => newXScale(d.start_offset_ms + d.duration_ms) + 5);
    
    this.spanGroups.selectAll('.error-indicator')
      .attr('cx', d => newXScale(d.start_offset_ms) - 8);
  }

  zoomIn() {
    this.svg.transition().duration(300).call(
      this.zoom.scaleBy, 1.5
    );
  }

  zoomOut() {
    this.svg.transition().duration(300).call(
      this.zoom.scaleBy, 1 / 1.5
    );
  }

  zoomToFit() {
    this.svg.transition().duration(500).call(
      this.zoom.transform,
      d3.zoomIdentity
    );
  }

  truncateText(text, maxLength) {
    return text.length > maxLength ? text.substring(0, maxLength) + '...' : text;
  }

  updateConfig(newConfig) {
    this.config = { ...this.config, ...newConfig };
    this.refresh();
  }

  refresh() {
    this.setupContainer();
    this.createScales();
    this.createVisualization();
  }

  destroy() {
    if (this.tooltip) {
      this.tooltip.remove();
    }
    this.container.innerHTML = '';
  }
}

// Gantt Chart Viewer
class GanttChartViewer {
  constructor(containerSelector, data, config = {}) {
    this.container = document.querySelector(containerSelector);
    this.data = data;
    this.config = config;
    
    this.init();
  }

  init() {
    // Initialize Gantt chart using dhtmlxGantt or similar library
    // This is a placeholder for the actual Gantt chart implementation
    this.createSimpleGantt();
  }

  createSimpleGantt() {
    // Simple Gantt chart implementation
    // In a real implementation, you'd use a library like dhtmlxGantt, Frappe Gantt, or build with D3.js
    
    const ganttContainer = this.container;
    ganttContainer.innerHTML = '';
    
    // Create header
    const header = document.createElement('div');
    header.className = 'gantt-header';
    header.innerHTML = `
      <h3>Gantt Chart View</h3>
      <p>Trace: ${this.data.trace_info?.workflow_name || 'Unknown'}</p>
    `;
    ganttContainer.appendChild(header);
    
    // Create chart area
    const chartArea = document.createElement('div');
    chartArea.className = 'gantt-chart-area';
    chartArea.style.height = '400px';
    chartArea.style.overflow = 'auto';
    
    // Build task rows
    this.data.tasks?.forEach(task => {
      const taskRow = document.createElement('div');
      taskRow.className = 'gantt-task-row';
      taskRow.innerHTML = `
        <div class="task-info">
          <span class="task-name">${task.text}</span>
          <span class="task-kind badge">${task.span_kind}</span>
        </div>
        <div class="task-bar" style="background-color: ${task.color}; width: ${task.duration * 10}px;">
          <span class="task-duration">${task.details.duration_ms}ms</span>
        </div>
      `;
      chartArea.appendChild(taskRow);
    });
    
    ganttContainer.appendChild(chartArea);
  }

  refresh() {
    this.createSimpleGantt();
  }

  destroy() {
    this.container.innerHTML = '';
  }
}

// Critical Path Viewer
class CriticalPathViewer {
  constructor(containerSelector, traceId, config = {}) {
    this.container = document.querySelector(containerSelector);
    this.traceId = traceId;
    this.config = config;
    this.data = null;
    
    this.init();
  }

  async init() {
    await this.loadCriticalPathData();
    this.createVisualization();
  }

  async loadCriticalPathData() {
    try {
      const response = await fetch(`/tracing/traces/${this.traceId}/critical_path.json`);
      this.data = await response.json();
    } catch (error) {
      console.error('Failed to load critical path data:', error);
      this.data = { critical_path: [], bottleneck_spans: [] };
    }
  }

  createVisualization() {
    const container = this.container;
    container.innerHTML = '';
    
    if (!this.data.critical_path || this.data.critical_path.length === 0) {
      container.innerHTML = '<div class="alert alert-info">No critical path data available</div>';
      return;
    }
    
    // Create header
    const header = document.createElement('div');
    header.className = 'critical-path-header';
    header.innerHTML = `
      <h3>Critical Path Analysis</h3>
      <div class="critical-path-stats">
        <span>Total Critical Time: ${this.data.total_critical_time}ms</span>
        <span>Critical Path Percentage: ${this.data.critical_path_percentage}%</span>
        <span>Bottlenecks: ${this.data.bottleneck_spans?.length || 0}</span>
      </div>
    `;
    container.appendChild(header);
    
    // Create path visualization
    const pathContainer = document.createElement('div');
    pathContainer.className = 'critical-path-visualization';
    
    let cumulativeTime = 0;
    this.data.critical_path.forEach((span, index) => {
      const isBottleneck = this.data.bottleneck_spans?.some(b => b.span_id === span.span_id);
      
      const spanElement = document.createElement('div');
      spanElement.className = `critical-path-span ${isBottleneck ? 'bottleneck' : ''}`;
      spanElement.innerHTML = `
        <div class="span-info">
          <div class="span-name">${span.name}</div>
          <div class="span-meta">
            <span class="span-kind">${span.kind}</span>
            <span class="span-duration">${span.duration_ms}ms</span>
          </div>
        </div>
        <div class="span-timeline">
          <div class="timeline-bar" style="width: ${(span.duration_ms / this.data.total_critical_time) * 100}%"></div>
        </div>
      `;
      
      if (index < this.data.critical_path.length - 1) {
        const arrow = document.createElement('div');
        arrow.className = 'path-arrow';
        arrow.innerHTML = '↓';
        pathContainer.appendChild(spanElement);
        pathContainer.appendChild(arrow);
      } else {
        pathContainer.appendChild(spanElement);
      }
    });
    
    container.appendChild(pathContainer);
    
    // Add bottleneck details
    if (this.data.bottleneck_spans && this.data.bottleneck_spans.length > 0) {
      const bottleneckSection = document.createElement('div');
      bottleneckSection.className = 'bottleneck-section';
      bottleneckSection.innerHTML = `
        <h4>Bottleneck Analysis</h4>
        ${this.data.bottleneck_spans.map(bottleneck => `
          <div class="bottleneck-item">
            <div class="bottleneck-name">${bottleneck.name}</div>
            <div class="bottleneck-impact">${bottleneck.percentage_of_critical_path}% of critical path</div>
            <div class="bottleneck-duration">${bottleneck.duration_ms}ms</div>
          </div>
        `).join('')}
      `;
      container.appendChild(bottleneckSection);
    }
  }

  refresh() {
    this.init();
  }

  destroy() {
    this.container.innerHTML = '';
  }
}

// Main Timeline Application
document.addEventListener('DOMContentLoaded', function() {
  if (!window.timelineData || !window.ganttData) {
    console.error('Timeline data not available');
    return;
  }
  
  let currentViewer = null;
  
  // Initialize with timeline view
  showTimelineView();
  
  // View switcher handlers
  document.getElementById('timeline-view')?.addEventListener('click', showTimelineView);
  document.getElementById('gantt-view')?.addEventListener('click', showGanttView);
  document.getElementById('critical-path-view')?.addEventListener('click', showCriticalPathView);
  
  // Control handlers
  document.getElementById('zoom-in')?.addEventListener('click', () => {
    if (currentViewer && currentViewer.zoomIn) {
      currentViewer.zoomIn();
    }
  });
  
  document.getElementById('zoom-out')?.addEventListener('click', () => {
    if (currentViewer && currentViewer.zoomOut) {
      currentViewer.zoomOut();
    }
  });
  
  document.getElementById('zoom-fit')?.addEventListener('click', () => {
    if (currentViewer && currentViewer.zoomToFit) {
      currentViewer.zoomToFit();
    }
  });
  
  // Option handlers
  document.getElementById('show-attributes')?.addEventListener('change', updateConfig);
  document.getElementById('group-by-kind')?.addEventListener('change', updateConfig);
  document.getElementById('highlight-errors')?.addEventListener('change', updateConfig);
  
  // Close details panel
  document.getElementById('close-details')?.addEventListener('click', () => {
    document.getElementById('span-details-panel').style.display = 'none';
  });
  
  function showTimelineView() {
    setActiveView('timeline');
    document.getElementById('timeline-visualization').style.display = 'block';
    document.getElementById('gantt-visualization').style.display = 'none';
    document.getElementById('critical-path-visualization').style.display = 'none';
    
    if (currentViewer) {
      currentViewer.destroy();
    }
    
    currentViewer = new TimelineViewer('#timeline-canvas', window.timelineData, window.timelineConfig);
  }
  
  function showGanttView() {
    setActiveView('gantt');
    document.getElementById('timeline-visualization').style.display = 'none';
    document.getElementById('gantt-visualization').style.display = 'block';
    document.getElementById('critical-path-visualization').style.display = 'none';
    
    if (currentViewer) {
      currentViewer.destroy();
    }
    
    currentViewer = new GanttChartViewer('#gantt-chart', window.ganttData, window.timelineConfig);
  }
  
  function showCriticalPathView() {
    setActiveView('critical-path');
    document.getElementById('timeline-visualization').style.display = 'none';
    document.getElementById('gantt-visualization').style.display = 'none';
    document.getElementById('critical-path-visualization').style.display = 'block';
    
    if (currentViewer) {
      currentViewer.destroy();
    }
    
    currentViewer = new CriticalPathViewer('#critical-path-canvas', window.traceId, window.timelineConfig);
  }
  
  function setActiveView(view) {
    document.querySelectorAll('.view-switcher .btn').forEach(btn => {
      btn.classList.remove('active');
    });
    document.getElementById(`${view}-view`)?.classList.add('active');
    window.timelineConfig.currentView = view;
  }
  
  function updateConfig() {
    window.timelineConfig.showAttributes = document.getElementById('show-attributes')?.checked;
    window.timelineConfig.groupByKind = document.getElementById('group-by-kind')?.checked;
    window.timelineConfig.highlightErrors = document.getElementById('highlight-errors')?.checked;
    
    if (currentViewer && currentViewer.updateConfig) {
      currentViewer.updateConfig(window.timelineConfig);
    }
  }
  
  // Handle window resize
  window.addEventListener('resize', () => {
    if (currentViewer && currentViewer.refresh) {
      setTimeout(() => currentViewer.refresh(), 100);
    }
  });
});