# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # Panel — a titled glass box with a flush list or padded body.
        #
        # The console's right-hand column is made of these; keeping it one
        # component stops "Failing now" and "Live runs" drifting apart.
        #
        # @example
        #   render(Molecules::Panel.new(title: "Live runs", icon: "activity",
        #                               action: "all traces", action_href: traces_path)) do
        #     rows...
        #   end
        #
        class Panel < Base
          # @param title [String]
          # @param icon [String, nil] leading Bootstrap Icons name
          # @param action [String, nil] label for the header link
          # @param action_href [String, nil]
          # @param pad [Boolean] pad the body instead of running it flush
          def initialize(title:, icon: nil, action: nil, action_href: nil, pad: false,
                         class: nil, **attrs)
            @title = title
            @icon = icon
            @action = action
            @action_href = action_href
            @pad = pad
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            div(class: tokens("raaf-panel", @class), **@attrs) do
              div(class: "raaf-panel-head") do
                h2(class: "raaf-panel-title") do
                  render Atoms::Icon.new(@icon, size: :sm) if @icon
                  plain @title
                end

                a(href: @action_href || "#", class: "raaf-panel-action") { @action } if @action
              end

              div(class: tokens("raaf-panel-body", { "raaf-panel-body--pad" => @pad })) { yield if block }
            end
          end
        end
      end
    end
  end
end
