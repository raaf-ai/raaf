# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # CodeBlock — a scrolling monospace panel for payloads and traces.
        #
        # Hashes and arrays are pretty-printed as JSON, so callers can pass
        # span attributes straight through without serialising first.
        #
        # @example
        #   render Atoms::CodeBlock.new(span.span_attributes)
        #
        class CodeBlock < Base
          HEIGHTS = %i[tall flush].freeze

          # @param content [String, Hash, Array] rendered as JSON when structured
          # @param height [Symbol, nil] :tall or :flush to lift the height cap
          def initialize(content = nil, height: nil, class: nil, **attrs)
            @content = content
            @height = height
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            pre(class: css, **@attrs) do
              block ? yield : plain(formatted)
            end
          end

          private

          def css
            tokens("raaf-code-block", modifier("raaf-code-block", @height, HEIGHTS), @class)
          end

          def formatted
            case @content
            when ::Hash, ::Array then ::JSON.pretty_generate(@content)
            else @content.to_s
            end
          rescue ::JSON::GeneratorError, ::Encoding::UndefinedConversionError
            @content.inspect
          end
        end
      end
    end
  end
end
