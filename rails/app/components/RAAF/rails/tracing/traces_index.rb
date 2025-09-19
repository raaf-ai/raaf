# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class TracesIndex < BaseComponent
        def initialize(traces:, stats: nil, params: {}, total_pages: 1, page: 1, per_page: 20, total_count: 0)
          @traces = traces
          @stats = stats
          @params = params
          @total_pages = total_pages
          @page = page
          @per_page = per_page
          @total_count = total_count
        end

        def view_template
          div(id: "tracing-dashboard", class: "p-6") do
            render_header
            render_connection_status
            render_filters
            render_stats if @stats
            render_traces_table
            render_last_updated
          end

          content_for :javascript do
            render_javascript
          end
        end

        private

        def render_header
          div(class: "sm:flex sm:items-center sm:justify-between mb-6") do
            div(class: "min-w-0 flex-1") do
              h1(class: "text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:truncate") { "Traces" }
              p(class: "mt-1 text-sm text-gray-500") { "Monitor and analyze your agent execution traces" }
            end

            div(class: "mt-4 flex sm:mt-0 sm:ml-4") do
              div(class: "flex space-x-3") do
                render_preline_button(
                  text: "Refresh",
                  variant: "secondary",
                  icon: "bi-arrow-clockwise",
                  id: "refresh-dashboard"
                )

                render_preline_button(
                  text: "Export JSON",
                  href: "/raaf/tracing/traces.json",
                  variant: "secondary",
                  icon: "bi-download"
                )
              end

              div(class: "flex items-center ml-4") do
                input(
                  type: "checkbox",
                  id: "auto-refresh-toggle",
                  checked: true,
                  class: "w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500"
                )
                label(for: "auto-refresh-toggle", class: "ml-2 text-sm font-medium text-gray-900") do
                  "Auto-refresh"
                end
              end
            end
          end
        end

        def render_connection_status
          div(
            id: "connection-status",
            class: "hidden mb-4 p-4 bg-blue-50 border border-blue-200 rounded-lg",
            role: "alert"
          ) do
            div(class: "flex") do
              div(class: "flex-shrink-0") do
                i(class: "bi bi-info-circle text-blue-400")
              end
              div(class: "ml-3") do
                span(class: "status-text text-sm text-blue-800") { "Connecting..." }
              end
            end
          end
        end

        def render_filters
          div(class: "bg-white p-6 rounded-lg shadow mb-6") do
            form_with(url: "/raaf/tracing/traces", method: :get, local: true, class: "grid grid-cols-1 gap-4 sm:grid-cols-6") do |form|
              div(class: "sm:col-span-2") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Search" }
                form.text_field(
                  :search,
                  placeholder: "Search traces...",
                  value: @params[:search],
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div(class: "sm:col-span-1") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Workflow" }
                form.select(
                  :workflow,
                  [["All Workflows", ""]] + workflow_options,
                  { selected: @params[:workflow] },
                  { class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm" }
                )
              end

              div(class: "sm:col-span-1") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Status" }
                form.select(
                  :status,
                  [
                    ["All Statuses", ""],
                    ["Completed", "completed"],
                    ["Failed", "failed"],
                    ["Running", "running"],
                    ["Pending", "pending"]
                  ],
                  { selected: @params[:status] },
                  { class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm" }
                )
              end

              div(class: "sm:col-span-1") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "Start Time" }
                form.datetime_local_field(
                  :start_time,
                  value: @params[:start_time],
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )
              end

              div(class: "sm:col-span-1") do
                label(class: "block text-sm font-medium text-gray-700 mb-1") { "End Time" }
                form.datetime_local_field(
                  :end_time,
                  value: @params[:end_time],
                  class: "block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                )

                div(class: "mt-4") do
                  form.submit("Filter", class: "w-full inline-flex justify-center items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500")
                end
              end
            end
          end
        end

        def render_stats
          return unless @stats

          div(class: "grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4 mb-8") do
            render_metric_card(
              title: "Total",
              value: @stats[:total],
              color: "blue",
              icon: "bi-diagram-3"
            )

            render_metric_card(
              title: "Completed",
              value: @stats[:completed],
              color: "green",
              icon: "bi-check-circle"
            )

            render_metric_card(
              title: "Failed",
              value: @stats[:failed],
              color: "red",
              icon: "bi-x-circle"
            )

            render_metric_card(
              title: "Running",
              value: @stats[:running],
              color: "yellow",
              icon: "bi-play-circle"
            )
          end
        end

        def render_traces_table
          div(id: "traces-table-container") do
            render TracesTable.new(
              traces: @traces,
              page: @page,
              total_pages: @total_pages,
              per_page: @per_page,
              total_count: @total_count,
              params: @params
            )
          end
        end

        def render_last_updated
          div(class: "mt-6 text-right text-sm text-gray-500") do
            plain "Last updated: "
            span(id: "last-updated") { Time.current.strftime("%Y-%m-%d %H:%M:%S") }
          end
        end

        def workflow_options
          # This would normally come from the controller/service
          # For now, returning empty array, but in real implementation:
          # RubyAIAgentsFactory::Tracing::TraceRecord.distinct.pluck(:workflow_name).compact.map { |w| [w, w] }
          []
        end

        def render_javascript
          script do
            plain <<~JAVASCRIPT
              // Live update functionality for traces
              class TracesLiveUpdate {
                constructor() {
                  this.autoRefreshEnabled = true;
                  this.refreshInterval = 5000; // 5 seconds
                  this.intervalId = null;
                  this.initialize();
                }

                initialize() {
                  this.setupEventHandlers();

                  if (this.autoRefreshEnabled) {
                    this.startAutoRefresh();
                  }

                  this.updateConnectionStatus('polling');
                }

                setupEventHandlers() {
                  const refreshBtn = document.getElementById('refresh-dashboard');
                  if (refreshBtn) {
                    refreshBtn.addEventListener('click', () => {
                      this.fetchUpdates();
                    });
                  }

                  const autoRefreshToggle = document.getElementById('auto-refresh-toggle');
                  if (autoRefreshToggle) {
                    autoRefreshToggle.addEventListener('change', (e) => {
                      this.autoRefreshEnabled = e.target.checked;
                      if (this.autoRefreshEnabled) {
                        this.startAutoRefresh();
                      } else {
                        this.stopAutoRefresh();
                      }
                    });
                  }
                }

                startAutoRefresh() {
                  this.stopAutoRefresh();
                  this.intervalId = setInterval(() => {
                    this.fetchUpdates();
                  }, this.refreshInterval);
                }

                stopAutoRefresh() {
                  if (this.intervalId) {
                    clearInterval(this.intervalId);
                    this.intervalId = null;
                  }
                }

                async fetchUpdates() {
                  try {
                    const response = await fetch(window.location.href, {
                      headers: {
                        'Accept': 'text/html',
                        'X-Requested-With': 'XMLHttpRequest'
                      }
                    });

                    if (response.ok) {
                      const html = await response.text();
                      this.updateTracesList(html);
                      this.updateLastUpdated();
                      const newTraceCount = document.querySelectorAll('[data-trace-id]').length;
                      if (this.lastTraceCount !== undefined && this.lastTraceCount !== newTraceCount) {
                        this.updateConnectionStatus('updated');
                      }
                      this.lastTraceCount = newTraceCount;
                    }
                  } catch (error) {
                    console.error('Failed to fetch updates:', error);
                    this.updateConnectionStatus('error');
                  }
                }

                updateTracesList(html) {
                  const container = document.getElementById('traces-table-container');
                  if (!container) return;

                  const currentTraces = new Set();
                  document.querySelectorAll('[data-trace-id]').forEach(tr => {
                    currentTraces.add(tr.dataset.traceId);
                  });

                  container.innerHTML = html;

                  document.querySelectorAll('[data-trace-id]').forEach(tr => {
                    if (!currentTraces.has(tr.dataset.traceId)) {
                      tr.classList.add('bg-green-50');
                      setTimeout(() => {
                        tr.classList.remove('bg-green-50');
                      }, 2000);
                    }
                  });
                }

                updateLastUpdated() {
                  const lastUpdated = document.getElementById('last-updated');
                  if (lastUpdated) {
                    lastUpdated.textContent = new Date().toLocaleString();
                  }
                }

                updateConnectionStatus(status) {
                  const statusElement = document.getElementById('connection-status');
                  if (statusElement) {
                    if (status === 'polling') {
                      statusElement.classList.remove('hidden');
                      statusElement.className = 'mb-4 p-4 bg-blue-50 border border-blue-200 rounded-lg';
                      statusElement.querySelector('.status-text').textContent = 'Live updates active (refreshing every 5 seconds)';
                      setTimeout(() => {
                        statusElement.classList.add('hidden');
                      }, 3000);
                    } else if (status === 'error') {
                      statusElement.classList.remove('hidden');
                      statusElement.className = 'mb-4 p-4 bg-yellow-50 border border-yellow-200 rounded-lg';
                      statusElement.querySelector('.status-text').textContent = 'Connection error - retrying...';
                      setTimeout(() => {
                        statusElement.classList.add('hidden');
                      }, 3000);
                    } else if (status === 'updated') {
                      statusElement.classList.remove('hidden');
                      statusElement.className = 'mb-4 p-4 bg-green-50 border border-green-200 rounded-lg';
                      statusElement.querySelector('.status-text').textContent = 'Updated!';
                      setTimeout(() => {
                        statusElement.classList.add('hidden');
                      }, 1000);
                    }
                  }
                }

                destroy() {
                  this.stopAutoRefresh();
                }
              }

              document.addEventListener('DOMContentLoaded', function() {
                window.tracesLiveUpdate = new TracesLiveUpdate();
              });
            JAVASCRIPT
          end
        end
      end
    end
  end
end