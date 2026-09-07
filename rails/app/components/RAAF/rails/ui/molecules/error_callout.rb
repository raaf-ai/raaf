# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # ErrorCallout — an exception class, its message and its backtrace.
        #
        # Used by the span inspector's Error tab and by the errors list, which
        # is why the backtrace is optional: a grouped error shows the class and
        # message only.
        #
        # @example
        #   render Molecules::ErrorCallout.new(
        #     klass: "Faraday::TimeoutError",
        #     message: "execution expired — POST /v2/companies/upsert",
        #     backtrace: span.backtrace
        #   )
        #
        class ErrorCallout < Base
          # @param klass [String] the exception class
          # @param message [String, nil]
          # @param backtrace [String, Array<String>, nil]
          def initialize(klass:, message: nil, backtrace: nil, class: nil, **attrs)
            @klass = klass
            @message = message
            @backtrace = backtrace
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: tokens("raaf-error-callout", @class), **@attrs) do
              div(class: "raaf-error-head") do
                span(class: "raaf-error-class") { @klass }
                p(class: "raaf-error-message") { @message } if @message
              end
              trace if lines.any?
            end
          end

          private

          def lines
            @lines ||= case @backtrace
                       when nil then []
                       when Array then @backtrace.map(&:to_s)
                       else @backtrace.to_s.split("\n")
                       end.reject(&:empty?)
          end

          def trace
            div(class: "raaf-error-trace") do
              render Atoms::Label.new("Backtrace")
              pre(class: "raaf-error-backtrace") { lines.join("\n") }
            end
          end
        end
      end
    end
  end
end
