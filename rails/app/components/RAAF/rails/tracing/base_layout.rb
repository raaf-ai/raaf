# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class BaseLayout < BaseComponent

      def initialize(title: "Dashboard", breadcrumb: nil)
        @title = title
        @breadcrumb = breadcrumb
      end

      def view_template(&block)
        html(lang: "en") do
          head do
            meta(charset: "utf-8")
            meta(name: "viewport", content: "width=device-width, initial-scale=1, shrink-to-fit=no")
            title { "Ruby AI Agents Factory Tracing - #{@title}" }

            # Tailwind CSS (required for Preline components)
            link(href: "https://cdn.tailwindcss.com", rel: "stylesheet")

            # Preline CSS
            link(href: "https://preline.co/assets/css/main.min.css", rel: "stylesheet")

            # Custom CSS for tracing-specific styles
            style do
              plain(tracing_styles)
            end

            csrf_meta_tags
            csp_meta_tag
          end

          body(class: "bg-gray-50", data: { controller: "auto-refresh", auto_refresh_interval_value: 30000 }) do
            div(class: "flex h-screen overflow-hidden") do
              render_sidebar
              div(class: "flex-1 flex flex-col overflow-hidden") do
                render_header
                render_main_content(&block)
              end
            end
            render_scripts
          end
        end
      end

      private

      def render_header
        header(class: "bg-white shadow-sm border-b flex-shrink-0") do
          div(class: "px-4 sm:px-6") do
            div(class: "flex justify-between items-center py-4") do
              div(class: "me-5 lg:me-0 lg:hidden") do
                a(href: "#", class: "flex-none text-xl font-semibold text-gray-800") do
                  "🔍 Ruby AI Agents Factory Tracing"
                end
              end

              div(class: "flex justify-end items-center gap-3") do
                # Auto-refresh indicator
                div(id: "connection-status", class: "hidden bg-blue-100 text-blue-800 px-3 py-1 rounded") do
                  span(class: "status-text") { "Connecting..." }
                end
              end
            end
          end
        end
      end

      def render_sidebar
        aside(id: "hs-application-sidebar", class: "w-64 bg-white border-r border-gray-200 flex-shrink-0") do
          div(class: "px-6 pt-4") do
            a(href: dashboard_path, class: "flex-none text-xl font-semibold text-gray-800") do
              "🔍 RAAF Tracing"
            end
          end

          nav(class: "hs-accordion-group p-6 w-full flex flex-col flex-wrap",
              data: { "hs-accordion-always-open": true }) do
            ul(class: "space-y-1") do
              render_sidebar_items
            end
          end
        end
      end

      def render_main_content(&block)
        main(class: "flex-1 overflow-auto") do
          div(class: "p-4 sm:p-6 space-y-4 sm:space-y-6") do
            # Breadcrumb if provided
            if @breadcrumb
              nav(class: "breadcrumb") do
                @breadcrumb.call
              end
            end

            # Main content area
            div(class: "space-y-6") do
              if block_given?
                component = block.call
                if component.respond_to?(:view_template)
                  render component  # Render Phlex component properly
                else
                  component  # For non-component content
                end
              end
            end
          end
        end
      end

      def render_scripts
        # Simple vanilla JavaScript for expand/collapse functionality using safe()
        script do
          safe(<<~JS)
            document.addEventListener('DOMContentLoaded', function() {
              console.log('🚀 Hierarchical spans JavaScript loaded!');

              // Initialize collapsed state
              function initializeCollapsedState() {
                const childrenRows = document.querySelectorAll('tr.span-children');
                console.log('👥 Found ' + childrenRows.length + ' children rows to hide');

                childrenRows.forEach(row => {
                  row.classList.add('hidden');
                  console.log('🙈 Hiding row for span ' + row.dataset.spanId);
                });
              }

              // Toggle children visibility
              function toggleChildren(button) {
                console.log('🎯 toggleChildren called for button:', button);

                const spanId = button.dataset.spanId;
                console.log('🔍 Toggling span ' + spanId);

                const childrenRows = document.querySelectorAll(
                  'tr.span-children[data-parent-span-id="' + spanId + '"]'
                );

                console.log('📊 Found ' + childrenRows.length + ' children rows for span ' + spanId);

                if (childrenRows.length === 0) {
                  console.log('ℹ️ No children rows found for span ' + spanId + ' (may be cross-trace relationship)');
                  return;
                }

                const isCurrentlyHidden = childrenRows[0].classList.contains('hidden');

                if (isCurrentlyHidden) {
                  // Expand: show children and change chevron to down
                  childrenRows.forEach(row => {
                    row.classList.remove('hidden');
                  });

                  button.textContent = '▼';
                  button.classList.add('bg-blue-100', 'border-blue-400', 'text-blue-800');
                  button.classList.remove('bg-gray-100', 'border-gray-300');

                } else {
                  // Collapse: hide children and change chevron to right
                  button.textContent = '▶';
                  button.classList.remove('bg-blue-100', 'border-blue-400', 'text-blue-800');
                  button.classList.add('bg-gray-100', 'border-gray-300');

                  childrenRows.forEach(row => {
                    row.classList.add('hidden');
                  });

                  // Also collapse any expanded grandchildren
                  childrenRows.forEach(row => {
                    const grandchildrenRows = document.querySelectorAll(
                      'tr.span-children[data-parent-span-id="' + row.dataset.spanId + '"]'
                    );
                    grandchildrenRows.forEach(grandchildRow => {
                      grandchildRow.classList.add('hidden');

                      const grandchildButton = grandchildRow.querySelector('.expand-button');
                      if (grandchildButton) {
                        grandchildButton.textContent = '▶';
                        grandchildButton.classList.remove('bg-blue-100', 'border-blue-400', 'text-blue-800');
                        grandchildButton.classList.add('bg-gray-100', 'border-gray-300');
                      }
                    });
                  });
                }
              }

              // Initialize collapsed state
              initializeCollapsedState();

              // Add click handlers to all expand buttons
              const expandButtons = document.querySelectorAll('.expand-button');
              console.log('🔘 Found ' + expandButtons.length + ' expand buttons to handle');

              expandButtons.forEach(button => {
                button.addEventListener('click', function(event) {
                  event.preventDefault();
                  event.stopPropagation();
                  toggleChildren(this);
                });
              });
            });
          JS
        end

        # Preline JS
        script(src: "https://preline.co/assets/js/preline.js")
      end

      def render_sidebar_items
        sidebar_items.each do |item|
          li do
            a(
              href: item[:path],
              class: "flex items-center gap-3 px-3 py-2 text-sm font-medium rounded-md #{
                item[:active] ? 'bg-gray-100 text-gray-900' : 'text-gray-700 hover:bg-gray-50'
              }"
            ) do
              # Icon would go here
              span { item[:label] }
            end
          end
        end
      end

      def sidebar_items
        # Complete list of RAAF tracing routes
        [
          {
            label: "Dashboard",
            path: dashboard_path,
            icon_name: "chart-bar",
            active: true
          },
          {
            label: "Traces",
            path: tracing_traces_path,
            icon_name: "squares-2x2",
            active: false
          },
          {
            label: "Spans",
            path: tracing_spans_path,
            icon_name: "list-bullet",
            active: false
          },
          {
            label: "Tool Spans",
            path: tools_tracing_spans_path,
            icon_name: "wrench",
            active: false
          },
          {
            label: "Flow Visualization",
            path: flows_tracing_spans_path,
            icon_name: "diagram-3",
            active: false
          },
          {
            label: "Performance",
            path: dashboard_performance_path,
            icon_name: "speedometer2",
            active: false
          },
          {
            label: "Costs",
            path: dashboard_costs_path,
            icon_name: "currency-dollar",
            active: false
          },
          {
            label: "Errors",
            path: dashboard_errors_path,
            icon_name: "exclamation-triangle",
            active: false
          },
          {
            label: "Timeline",
            path: tracing_timeline_path,
            icon_name: "clock-history",
            active: false
          },
          {
            label: "Search",
            path: tracing_search_path,
            icon_name: "search",
            active: false
          }
        ]
      end

      def tracing_styles
        <<~CSS
          .status-ok { color: #10b981; }
          .status-error { color: #ef4444; }
          .status-running { color: #f59e0b; }
          .status-pending { color: #6b7280; }

          .kind-agent { color: #3b82f6; }
          .kind-llm { color: #06b6d4; }
          .kind-tool { color: #10b981; }
          .kind-handoff { color: #f59e0b; }

          .metric-card {
            transition: all 0.2s ease-in-out;
          }

          .metric-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 25px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05);
          }
        CSS
      end

    end
    end
  end
end
