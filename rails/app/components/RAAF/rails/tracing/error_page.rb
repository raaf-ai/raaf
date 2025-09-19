# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      class ErrorPage < BaseComponent
        def initialize(error: nil, title: "Error", error_message: "An error occurred", back_path: "/raaf/tracing")
          @error = error
          @title = title
          @error_message = error_message
          @back_path = back_path
        end

        def view_template
          div(class: "min-h-screen bg-gray-50 flex flex-col justify-center py-12 sm:px-6 lg:px-8") do
            div(class: "sm:mx-auto sm:w-full sm:max-w-2xl") do
              div(class: "bg-white shadow-xl rounded-lg overflow-hidden") do
                div(class: "px-6 py-8 text-center") do
                  i(class: "bi bi-exclamation-triangle text-6xl text-red-500 mb-4")
                  h1(class: "text-3xl font-bold text-gray-900 mb-2") { @title }
                  p(class: "text-lg text-gray-600 mb-6") { @error_message }
                end

                if @error
                  div(class: "px-6 pb-6") do
                    div(class: "bg-red-50 border border-red-200 rounded-lg p-4 mb-6") do
                      h3(class: "text-sm font-medium text-red-800 mb-2") { "Error Details" }

                      div(class: "mb-3") do
                        p(class: "text-sm text-red-700 font-medium") { "Message:" }
                        p(class: "text-sm text-red-600 font-mono bg-red-100 p-2 rounded mt-1") { @error.message }
                      end

                      div(class: "mb-3") do
                        p(class: "text-sm text-red-700 font-medium") { "Type:" }
                        p(class: "text-sm text-red-600") { @error.class.name }
                      end

                      if @error.backtrace && @error.backtrace.any?
                        div do
                          p(class: "text-sm text-red-700 font-medium mb-2") { "Backtrace:" }
                          pre(class: "text-xs text-red-600 bg-red-100 p-3 rounded overflow-x-auto max-h-64") do
                            code { @error.backtrace.first(10).join("\n") }
                          end
                        end
                      end
                    end
                  end
                end

                div(class: "px-6 py-4 bg-gray-50 flex justify-center space-x-4") do
                  render_preline_button(
                    text: "Go Back",
                    href: @back_path,
                    variant: "primary",
                    icon: "bi-arrow-left"
                  )

                  render_preline_button(
                    text: "Dashboard",
                    href: "/raaf/tracing/dashboard",
                    variant: "secondary",
                    icon: "bi-house"
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