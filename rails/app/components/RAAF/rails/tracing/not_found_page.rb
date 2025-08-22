# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class NotFoundPage < Phlex::HTML
        def initialize(message: nil)
          @message = message || "The requested resource could not be found."
        end

        def view_template
          html(lang: "en") do
            head do
              meta(charset: "utf-8")
              meta(name: "viewport", content: "width=device-width, initial-scale=1")
              title { "RAAF Tracing - Not Found" }
              style { plain(css) }
            end

            body do
              div(class: "container") do
                div(class: "not-found-box") do
                  h1 { "404" }
                  h2 { "Page Not Found" }
                  p(class: "message") { @message }
                  
                  div(class: "actions") do
                    a(href: "/raaf", class: "button") { "← Back to Dashboard" }
                    a(href: "/raaf/tracing/traces", class: "button secondary") { "View All Traces" }
                  end
                end
              end
            end
          end
        end

        private

        def css
          <<~CSS
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body { 
              font-family: system-ui, -apple-system, sans-serif; 
              background: #f5f5f5;
              color: #333;
              padding: 20px;
            }
            .container {
              max-width: 600px;
              margin: 100px auto;
            }
            .not-found-box {
              background: white;
              padding: 60px 40px;
              border-radius: 8px;
              box-shadow: 0 2px 10px rgba(0,0,0,0.1);
              text-align: center;
            }
            h1 {
              font-size: 6em;
              color: #007bff;
              margin-bottom: 10px;
              font-weight: bold;
            }
            h2 {
              color: #666;
              margin-bottom: 20px;
              font-size: 1.5em;
            }
            .message {
              color: #888;
              margin: 20px 0 40px;
              line-height: 1.6;
            }
            .actions {
              display: flex;
              gap: 15px;
              justify-content: center;
            }
            .button {
              display: inline-block;
              background: #007bff;
              color: white;
              padding: 12px 24px;
              border-radius: 4px;
              text-decoration: none;
              transition: background 0.2s;
            }
            .button:hover {
              background: #0056b3;
            }
            .button.secondary {
              background: #6c757d;
            }
            .button.secondary:hover {
              background: #5a6268;
            }
          CSS
        end
      end
    end
  end
end