# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class SimpleDashboard < Phlex::HTML
        def initialize(title: "Tracing Dashboard")
          @title = title
        end

        def view_template
          html(lang: "en") do
            head do
              meta(charset: "utf-8")
              meta(name: "viewport", content: "width=device-width, initial-scale=1")
              title { "RAAF - #{@title}" }
              style { plain(css) }
            end

            body do
              render_header
              render_content
            end
          end
        end

        private

        def render_header
          header(class: "header") do
            h1 { "RAAF Tracing Dashboard" }
            nav do
              a(href: "/raaf") { "Main Dashboard" }
              a(href: "/raaf/dashboard") { "Tracing" }
              a(href: "/raaf/tracing/traces") { "Traces" }
              a(href: "/raaf/tracing/spans") { "Spans" }
              a(href: "/raaf/tracing/costs") { "Costs" }
            end
          end
        end

        def render_content
          main(class: "main") do
            div(class: "notice") do
              h2 { "⚠️ Database Setup Required" }
              p do
                plain "The RAAF Tracing feature requires database tables to be created. "
                plain "Please run the following migrations in your main application:"
              end
              
              div(class: "code-block") do
                pre do
                  code do
                    plain <<~MIGRATION
                      # Create migration file:
                      rails generate migration CreateRaafTracingTables

                      # Add to the migration:
                      create_table :raaf_tracing_traces do |t|
                        t.string :trace_id, null: false, index: { unique: true }
                        t.string :workflow_name
                        t.string :group_id
                        t.string :status
                        t.json :metadata
                        t.datetime :started_at
                        t.datetime :ended_at
                        t.timestamps
                      end

                      create_table :raaf_tracing_spans do |t|
                        t.string :span_id, null: false, index: { unique: true }
                        t.string :trace_id, index: true
                        t.string :parent_id, index: true
                        t.string :name
                        t.string :kind
                        t.string :status
                        t.json :span_attributes
                        t.json :events
                        t.datetime :start_time
                        t.datetime :end_time
                        t.float :duration_ms
                        t.timestamps
                      end

                      # Run migration:
                      rails db:migrate
                    MIGRATION
                  end
                end
              end
            end

            div(class: "info") do
              h3 { "About RAAF Tracing" }
              p do
                plain "RAAF Tracing provides comprehensive observability for your AI agent workflows:"
              end
              ul do
                li { "📊 Track execution traces and spans" }
                li { "⏱️ Monitor performance metrics" }
                li { "💰 Analyze token usage and costs" }
                li { "🔍 Debug agent interactions" }
                li { "📈 Visualize workflow timelines" }
              end
            end

            div(class: "features") do
              h3 { "Features" }
              div(class: "feature-grid") do
                feature_card("Trace Management", "Track complete workflow executions with detailed timing and status information")
                feature_card("Span Analysis", "Drill down into individual operations within traces")
                feature_card("Cost Tracking", "Monitor LLM token usage and associated costs")
                feature_card("Performance Metrics", "Analyze latency, throughput, and error rates")
                feature_card("Search & Filter", "Find specific traces and spans quickly")
                feature_card("Real-time Updates", "Live dashboard with WebSocket support")
              end
            end
          end
        end

        def feature_card(title, description)
          div(class: "feature-card") do
            h4 { title }
            p { description }
          end
        end

        def css
          <<~CSS
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body { 
              font-family: system-ui, -apple-system, sans-serif; 
              background: #f5f5f5;
              color: #333;
            }
            .header {
              background: white;
              padding: 20px 40px;
              border-bottom: 1px solid #e0e0e0;
              margin-bottom: 30px;
            }
            .header h1 {
              margin-bottom: 15px;
              color: #333;
            }
            nav {
              display: flex;
              gap: 20px;
            }
            nav a {
              color: #007bff;
              text-decoration: none;
              padding: 5px 10px;
              border-radius: 4px;
              transition: background 0.2s;
            }
            nav a:hover {
              background: #e3f2fd;
            }
            .main {
              padding: 0 40px;
              max-width: 1200px;
              margin: 0 auto;
            }
            .notice {
              background: #fff3cd;
              border: 1px solid #ffc107;
              padding: 20px;
              border-radius: 8px;
              margin-bottom: 30px;
            }
            .notice h2 {
              color: #856404;
              margin-bottom: 10px;
            }
            .notice p {
              color: #856404;
              margin-bottom: 15px;
              line-height: 1.6;
            }
            .code-block {
              background: #f8f9fa;
              border: 1px solid #dee2e6;
              border-radius: 4px;
              padding: 15px;
              margin-top: 10px;
              overflow-x: auto;
            }
            pre {
              margin: 0;
            }
            code {
              font-family: 'Monaco', 'Menlo', monospace;
              font-size: 0.9em;
              color: #212529;
            }
            .info, .features {
              background: white;
              padding: 30px;
              border-radius: 8px;
              margin-bottom: 30px;
            }
            .info h3, .features h3 {
              margin-bottom: 15px;
              color: #333;
            }
            .info p {
              color: #666;
              line-height: 1.6;
              margin-bottom: 15px;
            }
            .info ul {
              margin-left: 20px;
              color: #666;
            }
            .info li {
              margin-bottom: 10px;
              line-height: 1.6;
            }
            .feature-grid {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
              gap: 20px;
              margin-top: 20px;
            }
            .feature-card {
              background: #f8f9fa;
              padding: 20px;
              border-radius: 8px;
            }
            .feature-card h4 {
              color: #007bff;
              margin-bottom: 10px;
            }
            .feature-card p {
              color: #666;
              line-height: 1.5;
              font-size: 0.95em;
            }
          CSS
        end
      end
    end
  end
end