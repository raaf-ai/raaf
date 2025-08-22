# frozen_string_literal: true

module RAAF
  module Rails
    class SimpleDashboard < Phlex::HTML
      def initialize(title: "Dashboard", stats: {})
        @title = title
        @stats = stats
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
          h1 { "RAAF Dashboard" }
          nav do
            a(href: "/raaf/dashboard") { "Dashboard" }
            a(href: "/raaf/dashboard/agents") { "Agents" }
            a(href: "/raaf/dashboard/conversations") { "Conversations" }
            a(href: "/raaf/dashboard/analytics") { "Analytics" }
          end
        end
      end

      def render_content
        main(class: "main") do
          div(class: "welcome") do
            h2 { "Welcome to Ruby AI Agents Factory" }
            p { "RAAF provides a comprehensive framework for building and managing AI agents in Ruby applications." }
          end

          if @stats.any?
            div(class: "stats") do
              @stats.each do |label, value|
                div(class: "stat-card") do
                  div(class: "stat-value") { value.to_s }
                  div(class: "stat-label") { label.to_s.humanize }
                end
              end
            end
          end

          div(class: "info") do
            h3 { "Getting Started" }
            ul do
              li { "Configure your AI agents in the Agents section" }
              li { "View conversation history and analytics" }
              li { "Monitor performance and costs in Analytics" }
            end
          end
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
          .welcome {
            background: white;
            padding: 30px;
            border-radius: 8px;
            margin-bottom: 30px;
          }
          .welcome h2 {
            margin-bottom: 10px;
            color: #333;
          }
          .welcome p {
            color: #666;
            line-height: 1.6;
          }
          .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
          }
          .stat-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
          }
          .stat-value {
            font-size: 2em;
            font-weight: bold;
            color: #007bff;
            margin-bottom: 5px;
          }
          .stat-label {
            color: #666;
            font-size: 0.9em;
          }
          .info {
            background: white;
            padding: 30px;
            border-radius: 8px;
          }
          .info h3 {
            margin-bottom: 15px;
            color: #333;
          }
          .info ul {
            margin-left: 20px;
            color: #666;
          }
          .info li {
            margin-bottom: 10px;
            line-height: 1.6;
          }
        CSS
      end
    end
  end
end