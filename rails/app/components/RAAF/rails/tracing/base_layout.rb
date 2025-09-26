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

            # Highlight.js CSS for syntax highlighting
            link(href: "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/default.min.css", rel: "stylesheet")

            # Custom CSS for tracing-specific styles
            style do
              plain(tracing_styles)
            end

            csrf_meta_tags
            csp_meta_tag
          end

          body(class: "bg-gray-50", data: { controller: "auto-refresh tooltip", auto_refresh_interval_value: 30000 }) do
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
        # Use ES6 modules to properly load and initialize Stimulus
        script(type: "module") do
          safe(<<~JS)
            // Import and initialize Stimulus properly
            import { Application, Controller } from "https://unpkg.com/@hotwired/stimulus/dist/stimulus.js"

            // Start Stimulus application
            const application = Application.start()

            // Register span-detail controller
            class SpanDetailController extends Controller {
                  static targets = ["toggleIcon", "section"]
                  static values = { debug: { type: Boolean, default: false } }

                  connect() {
                    if (this.debugValue) {
                      console.log("🔍 SpanDetail controller connected")
                    }
                    this.initializeSectionStates()
                  }

                  toggleSection(event) {
                    event.preventDefault()

                    const button = event.currentTarget
                    const targetId = button.dataset.target
                    const section = document.getElementById(targetId)
                    const previewSection = document.getElementById(targetId + '-preview')
                    const icon = button.querySelector('.toggle-icon')

                    // Check if this is an expandable text section (has both preview and full sections)
                    if (previewSection && section) {
                      this.toggleExpandableText(previewSection, section, button)
                      return
                    }

                    // Regular section toggle
                    if (!section) {
                      console.warn(`No section found with ID: ${targetId}`)
                      return
                    }

                    this.performToggle(section, icon, button)
                  }

                  toggleExpandableText(previewSection, fullSection, button) {
                    const isShowingPreview = !previewSection.classList.contains('hidden')

                    if (isShowingPreview) {
                      // Show full text, hide preview
                      previewSection.classList.add('hidden')
                      fullSection.classList.remove('hidden')
                      button.textContent = 'Show Less'
                    } else {
                      // Show preview, hide full text
                      previewSection.classList.remove('hidden')
                      fullSection.classList.add('hidden')
                      button.textContent = 'Show Full Text'
                    }

                    if (this.debugValue) {
                      console.log(`🔍 Toggled expandable text: showing ${isShowingPreview ? 'full' : 'preview'}`)
                    }
                  }

                  performToggle(section, icon, button) {
                    if (section.classList.contains('hidden')) {
                      section.classList.remove('hidden')
                      if (icon) {
                        icon.classList.remove('bi-chevron-right')
                        icon.classList.add('bi-chevron-down')
                      }
                    } else {
                      section.classList.add('hidden')
                      if (icon) {
                        icon.classList.remove('bi-chevron-down')
                        icon.classList.add('bi-chevron-right')
                      }
                    }
                  }

                  initializeSectionStates() {
                    const collapsedSections = this.element.querySelectorAll('[data-initially-collapsed="true"]')
                    collapsedSections.forEach(section => {
                      section.classList.add('hidden')
                    })
                  }

                  copyToClipboard(event) {
                    event.preventDefault()

                    const button = event.currentTarget
                    const value = button.dataset.value

                    if (!value) {
                      console.warn('No value found to copy')
                      return
                    }

                    navigator.clipboard.writeText(value).then(() => {
                      const icon = button.querySelector('i')
                      if (icon) {
                        icon.classList.remove('bi-clipboard')
                        icon.classList.add('bi-clipboard-check', 'text-green-600')

                        setTimeout(() => {
                          icon.classList.remove('bi-clipboard-check', 'text-green-600')
                          icon.classList.add('bi-clipboard')
                        }, 1500)
                      }
                    }).catch(err => {
                      console.error('Failed to copy value: ', err)
                    })
                  }

                  toggleValue(event) {
                    event.preventDefault()

                    const button = event.currentTarget
                    const targetId = button.dataset.target
                    const preview = document.getElementById(`${targetId}-preview`)
                    const full = document.getElementById(`${targetId}-full`)

                    if (this.debugValue) {
                      console.log(`🔍 toggleValue called with targetId: ${targetId}`)
                      console.log(`🔍 Looking for preview element: ${targetId}-preview`)
                      console.log(`🔍 Looking for full element: ${targetId}-full`)
                      console.log(`🔍 Preview element found:`, preview)
                      console.log(`🔍 Full element found:`, full)
                    }

                    if (!preview || !full) {
                      console.warn(`Value elements not found for: ${targetId}`)
                      console.warn(`Preview element (${targetId}-preview):`, preview)
                      console.warn(`Full element (${targetId}-full):`, full)
                      return
                    }

                    if (full.classList.contains('hidden')) {
                      preview.classList.add('hidden')
                      full.classList.remove('hidden')
                      // Store original text if not already stored
                      if (!button.dataset.originalText) {
                        button.dataset.originalText = button.textContent
                      }
                      button.textContent = 'Show Less'
                    } else {
                      preview.classList.remove('hidden')
                      full.classList.add('hidden')
                      // Restore original text if available, otherwise use generic text
                      button.textContent = button.dataset.originalText || 'Show More'
                    }

                    if (this.debugValue) {
                      console.log(`🔍 Toggle completed. Full element hidden: ${full.classList.contains('hidden')}`)
                    }
                  }

                  disconnect() {
                    if (this.debugValue) {
                      console.log("🔍 SpanDetail controller disconnected")
                    }
                  }
            }

            // Register auto-refresh controller (basic implementation)
            class AutoRefreshController extends Controller {
              static values = { interval: Number }

              connect() {
                console.log("🔄 Auto-refresh controller connected")
              }
            }

            // Register tooltip controller (basic implementation)
            class TooltipController extends Controller {
              connect() {
                console.log("💬 Tooltip controller connected")
              }
            }

            // JSON highlighting controller
            class JsonHighlightController extends Controller {
              static targets = ["json"]

              connect() {
                console.log("🎨 JSON highlight controller connected")
                this.highlightAll()
              }

              highlightAll() {
                this.jsonTargets.forEach(element => {
                  this.highlightElement(element)
                })
              }

              highlightElement(element) {
                if (!window.hljs) {
                  // If highlight.js hasn't loaded yet, retry after a short delay
                  setTimeout(() => this.highlightElement(element), 100)
                  return
                }

                try {
                  // Ensure the element has the correct class for JSON highlighting
                  element.classList.add('language-json')

                  // Apply syntax highlighting
                  window.hljs.highlightElement(element)

                  console.log("🎨 Applied JSON syntax highlighting to element")
                } catch (error) {
                  console.warn('Failed to highlight JSON:', error)
                }
              }
            }

            // Register all controllers
            application.register("span-detail", SpanDetailController)
            application.register("auto-refresh", AutoRefreshController)
            application.register("tooltip", TooltipController)
            application.register("json-highlight", JsonHighlightController)

            console.log("✅ All RAAF Stimulus controllers registered")

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

        # Highlight.js for syntax highlighting
        script(src: "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js")
        script(src: "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/json.min.js")

        # Initialize highlight.js after loading
        script do
          safe(<<~JS)
            // Initialize highlight.js when it loads
            document.addEventListener('DOMContentLoaded', function() {
              if (typeof hljs !== 'undefined') {
                console.log('✅ Highlight.js loaded, initializing syntax highlighting');
                hljs.highlightAll();
              } else {
                console.warn('⚠️ Highlight.js not loaded');
              }
            });
          JS
        end

        # Preline JS
        script(src: "https://preline.co/assets/js/preline.js")

        # Debug script for tooltip troubleshooting
        script do
          safe(<<~JS)
            // Debug tooltips after all scripts load
            window.addEventListener('load', function() {
              console.log('🔧 RAAF Tooltip Debug: Window loaded');

              setTimeout(function() {
                // Check if Preline is loaded
                if (typeof window.HSTooltip !== 'undefined') {
                  console.log('✅ HSTooltip available:', typeof window.HSTooltip);

                  try {
                    window.HSTooltip.autoInit();
                    console.log('✅ HSTooltip.autoInit() called');
                  } catch (e) {
                    console.error('❌ HSTooltip.autoInit() error:', e);
                  }

                  // Count tooltip elements
                  const tooltips = document.querySelectorAll('.hs-tooltip');
                  const toggles = document.querySelectorAll('.hs-tooltip-toggle');
                  console.log(`🎯 Found ${tooltips.length} tooltip containers, ${toggles.length} toggles`);

                } else {
                  console.warn('⚠️ HSTooltip not available');
                  console.log('Available HS objects:', Object.keys(window).filter(k => k.startsWith('HS')));
                }
              }, 500);
            });
          JS
        end
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

          /* Markdown prose styles for RAAF tracing */
          .prose {
            color: #374151;
            max-width: none;
          }

          .prose h1 {
            font-size: 1.5em;
            font-weight: 700;
            margin: 0.67em 0;
            color: #111827;
          }

          .prose h2 {
            font-size: 1.3em;
            font-weight: 600;
            margin: 0.6em 0 0.4em 0;
            color: #1f2937;
          }

          .prose h3 {
            font-size: 1.1em;
            font-weight: 600;
            margin: 0.5em 0 0.3em 0;
            color: #374151;
          }

          .prose p {
            margin: 0.75em 0;
            line-height: 1.6;
          }

          .prose ul, .prose ol {
            margin: 0.75em 0;
            padding-left: 1.5em;
          }

          .prose li {
            margin: 0.25em 0;
          }

          .prose code {
            background-color: #f3f4f6;
            padding: 0.125em 0.25em;
            border-radius: 0.25rem;
            font-size: 0.875em;
            font-family: ui-monospace, SFMono-Regular, 'Cascadia Code', 'Roboto Mono', Menlo, Monaco, Consolas, monospace;
            color: #dc2626;
          }

          .prose pre {
            background-color: #f9fafb;
            border: 1px solid #e5e7eb;
            border-radius: 0.5rem;
            padding: 1rem;
            overflow-x: auto;
            margin: 1em 0;
            font-size: 0.875em;
          }

          .prose pre code {
            background-color: transparent;
            padding: 0;
            color: #374151;
          }

          .prose blockquote {
            border-left: 4px solid #e5e7eb;
            margin: 1em 0;
            padding-left: 1rem;
            color: #6b7280;
            font-style: italic;
          }

          .prose strong {
            font-weight: 600;
            color: #111827;
          }

          .prose em {
            font-style: italic;
          }

          .prose a {
            color: #2563eb;
            text-decoration: underline;
          }

          .prose a:hover {
            color: #1d4ed8;
          }

          .prose table {
            width: 100%;
            border-collapse: collapse;
            margin: 1em 0;
          }

          .prose th, .prose td {
            border: 1px solid #e5e7eb;
            padding: 0.5em;
            text-align: left;
          }

          .prose th {
            background-color: #f9fafb;
            font-weight: 600;
          }

          /* Smaller prose for compact areas */
          .prose-sm {
            font-size: 0.875rem;
          }

          .prose-sm h1 { font-size: 1.25em; }
          .prose-sm h2 { font-size: 1.125em; }
          .prose-sm h3 { font-size: 1em; }
          .prose-sm p { margin: 0.5em 0; }
          .prose-sm ul, .prose-sm ol { margin: 0.5em 0; }
          .prose-sm pre { padding: 0.75rem; font-size: 0.8125em; }
          .prose-sm code { font-size: 0.8125em; }

          /* Custom highlight.js overrides for better JSON visibility */
          .hljs {
            background: white !important;
            color: #24292e !important;
          }

          .hljs-string {
            color: #032f62 !important;
          }

          .hljs-number {
            color: #005cc5 !important;
          }

          .hljs-literal {
            color: #005cc5 !important;
          }

          .hljs-attr {
            color: #6f42c1 !important;
          }

          .hljs-punctuation {
            color: #24292e !important;
          }

          .hljs-keyword {
            color: #d73a49 !important;
          }

          .hljs-built_in {
            color: #005cc5 !important;
          }

          /* Ensure JSON braces and brackets are visible */
          .language-json .hljs-punctuation,
          .language-json .hljs-bracket {
            color: #24292e !important;
            font-weight: bold;
          }
        CSS
      end

    end
    end
  end
end
