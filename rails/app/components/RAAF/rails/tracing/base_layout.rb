# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class BaseLayout < Phlex::HTML
      include Phlex::Rails::Helpers::CSRFMetaTags
      include Phlex::Rails::Helpers::CSPMetaTag
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::Routes

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

            # Preline CSS
            link(href: "https://preline.co/assets/css/main.min.css", rel: "stylesheet")

            # Custom CSS for tracing-specific styles
            style do
              plain(tracing_styles)
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
        header(class: "bg-white shadow-sm border-b") do
          div(class: "container mx-auto") do
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
        aside(id: "hs-application-sidebar", class: "w-64 bg-white border-r border-gray-200 h-full") do
          div(class: "px-6 pt-4") do
            a(href: "/raaf/tracing/dashboard", class: "flex-none text-xl font-semibold text-gray-800") do
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
        main(class: "w-full lg:ps-64") do
          div(class: "p-4 sm:p-6 space-y-4 sm:space-y-6") do
            # Breadcrumb if provided
            if @breadcrumb
              nav(class: "breadcrumb") do
                @breadcrumb.call
              end
            end

            # Main content area
            div(class: "space-y-6", &block)
          end
        end
      end

      def render_scripts
        # Preline JS
        script(src: "https://preline.co/assets/js/preline.js")

        # Custom JS
        script do
          plain(tracing_scripts)
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
        # Only include routes that actually exist in the RAAF engine
        [
          {
            label: "Dashboard",
            path: "/raaf/tracing/dashboard",
            icon_name: "chart-bar",
            active: true  # Default to dashboard being active
          },
          {
            label: "Traces",
            path: "/raaf/tracing/traces",
            icon_name: "squares-2x2",
            active: false
          },
          {
            label: "Spans",
            path: "/raaf/tracing/spans",
            icon_name: "list-bullet",
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
end
