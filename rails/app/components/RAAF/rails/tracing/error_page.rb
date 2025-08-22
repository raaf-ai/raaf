# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class ErrorPage < Phlex::HTML
        def initialize(error: nil, title: "Error")
          @error = error
          @title = title
        end

        def view_template
          html(lang: "en") do
            head do
              meta(charset: "utf-8")
              meta(name: "viewport", content: "width=device-width, initial-scale=1")
              title { "RAAF Tracing - #{@title}" }
              style { plain(css) }
            end

            body do
              div(class: "container") do
                div(class: "error-box") do
                  h1 { "🚨 Error Occurred" }
                  
                  if @error
                    div(class: "error-details") do
                      h2 { "Error Details:" }
                      p(class: "error-message") { @error.message }
                      p(class: "error-class") { "Type: #{@error.class.name}" }
                      
                      if @error.backtrace && @error.backtrace.any?
                        div(class: "backtrace") do
                          h3 { "Backtrace:" }
                          pre do
                            code { @error.backtrace.first(10).join("\n") }
                          end
                        end
                      end
                    end
                  else
                    p { "An unexpected error occurred. Please try again later." }
                  end
                  
                  div(class: "actions") do
                    a(href: "/raaf", class: "button") { "← Back to Dashboard" }
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
              max-width: 800px;
              margin: 50px auto;
            }
            .error-box {
              background: white;
              padding: 40px;
              border-radius: 8px;
              box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            h1 {
              color: #d32f2f;
              margin-bottom: 20px;
              font-size: 2em;
            }
            h2 {
              color: #666;
              margin: 20px 0 10px;
              font-size: 1.2em;
            }
            h3 {
              color: #666;
              margin: 15px 0 10px;
              font-size: 1em;
            }
            .error-message {
              background: #ffebee;
              color: #c62828;
              padding: 15px;
              border-radius: 4px;
              margin: 10px 0;
              font-family: monospace;
            }
            .error-class {
              color: #666;
              margin: 10px 0;
              font-style: italic;
            }
            .backtrace {
              margin-top: 20px;
            }
            pre {
              background: #f5f5f5;
              padding: 15px;
              border-radius: 4px;
              overflow-x: auto;
            }
            code {
              font-family: 'Monaco', 'Menlo', monospace;
              font-size: 0.9em;
              color: #555;
            }
            .actions {
              margin-top: 30px;
            }
            .button {
              display: inline-block;
              background: #007bff;
              color: white;
              padding: 10px 20px;
              border-radius: 4px;
              text-decoration: none;
              transition: background 0.2s;
            }
            .button:hover {
              background: #0056b3;
            }
          CSS
        end
      end
    end
  end
end