# frozen_string_literal: true

module RubyAIAgentsFactory
  module Tracing
    class BaseLayout < Phlex::HTML
      include Phlex::Rails::Helpers::CSRFMetaTags
      include Phlex::Rails::Helpers::CSPMetaTag
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::Routes
      include Components::Preline

      def initialize(title: "Dashboard", breadcrumb: nil)
        @title = title
        @breadcrumb = breadcrumb
      end

      def template(&block)
        html(lang: "en") do
          head do
            meta(charset: "utf-8")
            meta(name: "viewport", content: "width=device-width, initial-scale=1, shrink-to-fit=no")
            title { "OpenAI Agents Tracing - #{@title}" }

            # Preline CSS
            link(href: "https://preline.co/assets/css/main.min.css", rel: "stylesheet")

            # Custom CSS for tracing-specific styles
            style do
              raw(tracing_styles)
            end

            csrf_meta_tags
            csp_meta_tag
          end

          body(class: "bg-gray-50") do
            render_header
            render_sidebar
            render_main_content(&block)
            render_scripts
          end
        end
      end

      private

      def render_header
        Header(class: "bg-white shadow-sm border-b") do
          Container do
            Flex(justify: :between, align: :center, class: "py-4") do
              Container(class: "me-5 lg:me-0 lg:hidden") do
                Link(href: "#", class: "flex-none text-xl font-semibold text-gray-800") do
                  "🔍 OpenAI Agents Tracing"
                end
              end

              Flex(justify: :end, align: :center, gap: 3) do
                # Auto-refresh indicator
                Alert(id: "connection-status", variant: :info, class: "hidden") do
                  Typography("Connecting...", class: "status-text")
                end
              end
            end
          end
        end
      end

      def render_sidebar
        Sidebar(id: "hs-application-sidebar", class: "w-64 bg-white border-r border-gray-200 h-full") do
          Container(class: "px-6 pt-4") do
            Link(href: root_path, class: "flex-none text-xl font-semibold text-gray-800") do
              "🔍 OpenAI Agents Tracing"
            end
          end

          Navs(class: "hs-accordion-group p-6 w-full flex flex-col flex-wrap",
               data: { "hs-accordion-always-open": true }) do
            List(class: "space-y-1") do
              render_sidebar_items
            end
          end
        end
      end

      def render_main_content(&block)
        Main(class: "w-full lg:ps-64") do
          Container(class: "p-4 sm:p-6 space-y-4 sm:space-y-6") do
            # Breadcrumb if provided
            if @breadcrumb
              Breadcrumb do
                @breadcrumb.call
              end
            end

            # Main content area
            Container(class: "space-y-6", &block)
          end
        end
      end

      def render_scripts
        # Preline JS
        script(src: "https://preline.co/assets/js/preline.js")

        # Custom JS
        script do
          raw(tracing_scripts)
        end
      end

      def render_sidebar_items
        sidebar_items.each do |item|
          ListGroup do
            Link(
              href: item[:path],
              class: "flex items-center gap-3 px-3 py-2 text-sm font-medium rounded-md #{
                item[:active] ? "bg-gray-100 text-gray-900" : "text-gray-700 hover:bg-gray-50"
              }"
            ) do
              # Icon would go here
              Typography(item[:label])
            end
          end
        end
      end

      def sidebar_items
        [
          {
            label: "Dashboard",
            path: dashboard_path,
            icon_name: "chart-bar",
            active: controller_name == "dashboard"
          },
          {
            label: "Traces",
            path: traces_path,
            icon_name: "squares-2x2",
            active: controller_name == "traces"
          },
          {
            label: "Spans",
            path: spans_path,
            icon_name: "list-bullet",
            active: controller_name == "spans" && action_name != "tools"
          },
          {
            label: "Tool Calls",
            path: tools_path,
            icon_name: "wrench-screwdriver",
            active: action_name == "tools"
          },
          {
            label: "Flow Visualization",
            path: flows_path,
            icon_name: "squares-plus",
            active: action_name == "flows"
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

      def tracing_scripts
        <<~JS
          // Auto-refresh functionality
          function enableAutoRefresh(interval = 30000) {
            setInterval(() => {
              if (document.hidden) return; // Don't refresh if tab is not active
              window.location.reload();
            }, interval);
          }
        JS
      end
    end
  end
end
