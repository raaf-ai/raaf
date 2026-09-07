# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # EmptyState — what a list shows when it has nothing to show.
        #
        # @example
        #   render Molecules::EmptyState.new(
        #     icon: "inbox", title: "No spans yet",
        #     text: "Runs appear here as soon as an agent is traced."
        #   )
        #
        class EmptyState < Base
          def initialize(title:, text: nil, icon: nil, tone: nil, class: nil, **attrs)
            @title = title
            @text = text
            @icon = icon
            @tone = tone
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: tokens("raaf-empty-state", @class), **@attrs) do
              render Atoms::IconBox.new(@icon, tone: @tone, size: :lg) if @icon
              p(class: "raaf-empty-state-title") { @title }
              p(class: "raaf-empty-state-text") { @text } if @text
              div(class: "raaf-empty-state-actions", &block) if block
            end
          end
        end
      end
    end
  end
end
