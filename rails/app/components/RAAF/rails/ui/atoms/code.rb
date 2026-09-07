# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Code — an inline monospace pill for ids, model names and paths.
        #
        # @example
        #   render Atoms::Code.new(span.span_id)
        #
        class Code < Base
          def initialize(content = nil, class: nil, **attrs)
            @content = content
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            code(class: tokens("raaf-code", @class), **@attrs) { slot(@content, &block) }
          end
        end
      end
    end
  end
end
