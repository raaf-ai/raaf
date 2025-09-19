# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class NotFoundPage < BaseComponent
        def initialize(message: nil, title: "Page Not Found")
          @message = message || "The requested resource could not be found."
          @title = title
        end

        def view_template
          div(class: "min-h-screen bg-gray-50 flex flex-col justify-center py-12 sm:px-6 lg:px-8") do
            div(class: "sm:mx-auto sm:w-full sm:max-w-md") do
              div(class: "bg-white shadow-xl rounded-lg overflow-hidden") do
                div(class: "px-6 py-8 text-center") do
                  div(class: "text-6xl font-bold text-blue-600 mb-4") { "404" }
                  h1(class: "text-2xl font-bold text-gray-900 mb-2") { @title }
                  p(class: "text-lg text-gray-600 mb-8") { @message }
                end

                div(class: "px-6 py-4 bg-gray-50 flex flex-col sm:flex-row sm:justify-center gap-3") do
                  render_preline_button(
                    text: "Dashboard",
                    href: "/raaf/dashboard",
                    variant: "primary",
                    icon: "bi-house"
                  )

                  render_preline_button(
                    text: "View Traces",
                    href: "/raaf/tracing/traces",
                    variant: "secondary",
                    icon: "bi-diagram-3"
                  )
                end
              end
            end
          end
        end
      end
    end
  end
end