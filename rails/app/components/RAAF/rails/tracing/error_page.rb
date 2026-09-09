# frozen_string_literal: true

module RAAF
  module Rails
    module Tracing
      ##
      # What a reader meets when something has already gone wrong.
      #
      # The worst screen in the console to leave in the light theme, because
      # it is the one that arrives unannounced: a white card dropped into the
      # dark shell reads as a second failure on top of the first.
      #
      class ErrorPage < BaseComponent
        def initialize(error: nil, title: "Something went wrong",
                       error_message: "The console could not finish this request.",
                       back_path: "/raaf/tracing")
          @error = error
          @title = title
          @error_message = error_message
          @back_path = back_path
        end

        def view_template
          div(class: "raaf-page") do
            render Organisms::RecordHead.new(
              title: @title,
              description: @error_message,
              status: "error",
              meta: @error&.class&.name
            )

            details if @error
            actions
          end
        end

        private

        def details
          render(Organisms::Card.new(title: "What failed")) do
            render Molecules::KeyValueList.new(
              pairs: { "Message" => @error.message.to_s, "Type" => @error.class.name },
              layout: :rows, mono: true
            )

            backtrace if @error.backtrace&.any?
          end
        end

        # Ten frames: enough to name the call that failed and the path into
        # it, without turning the page into a log.
        def backtrace
          render(Molecules::Field.new(label: "Backtrace",
                                      hint: "The first ten frames.")) do
            render Atoms::CodeBlock.new(@error.backtrace.first(10).join("\n"), height: :tall)
          end
        end

        def actions
          div(class: "raaf-cluster") do
            render Atoms::Button.new(label: "Go back", icon: "arrow-left", href: @back_path)
            render Atoms::Button.new(label: "Overview", icon: "house", variant: :secondary,
                                     href: dashboard_path)
          end
        end
      end
    end
  end
end
