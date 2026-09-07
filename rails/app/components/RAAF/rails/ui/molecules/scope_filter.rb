# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # ScopeFilter — the filter chip that opens a filter strip.
        #
        # The design draws it as a chip reading `workflow:Discovery::Pipeline`
        # behind a funnel, filling the row. It has to be settable as well as
        # readable, so the value is a `<select>` wearing the chip: the whole
        # control is a GET form that applies on change, which keeps it working
        # without JavaScript beyond the one-line `auto-submit` controller and
        # keeps the chosen scope in the URL.
        #
        # Chips were the alternative and do not survive contact with the data —
        # this console has 54 distinct workflow names.
        #
        # @example
        #   render Molecules::ScopeFilter.new(
        #     name: "workflow", value: params[:workflow], options: workflows,
        #     action: tracing_traces_path, prefix: "workflow"
        #   )
        #
        class ScopeFilter < Base
          # @param name [String] the query parameter this sets
          # @param value [String, nil] the current value
          # @param options [Array<String>, Array<Array(String, String)>] the
          #   choices, either as plain strings where the label is the value, or
          #   as `[label, value]` pairs where they differ — a policy is chosen
          #   by name and filtered by id.
          # @param action [String] form target
          # @param prefix [String] shown before the value, as in `workflow:`
          # @param icon [String] leading Bootstrap Icons name
          # @param blank_label [String] the label for "no filter"
          # @param carry [Hash] other parameters to preserve on submit
          def initialize(name:, value:, options:, action:, prefix:, icon: "funnel",
                         blank_label: "all", carry: {}, class: nil, **attrs)
            @name = name
            @value = value.presence
            @options = Array(options).compact
            @action = action
            @prefix = prefix
            @icon = icon
            @blank_label = blank_label
            @carry = carry.compact.reject { |_, v| v.to_s.empty? }
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            form(action: @action, method: "get",
                 class: tokens("raaf-scope", { "is-active" => @value }, @class),
                 data: { controller: "auto-submit", action: "change->auto-submit#submit" },
                 **@attrs) do
              render Atoms::Icon.new(@icon, size: :sm, tone: :muted)
              span(class: "raaf-scope-prefix") { "#{@prefix}:" }
              field
              @carry.each { |key, value| input(type: "hidden", name: key.to_s, value: value) }
            end
          end

          private

          def field
            select(name: @name, class: "raaf-scope-select",
                   "aria-label": "Filter by #{@prefix}") do
              option(value: "", selected: @value.nil?) { @blank_label }

              @options.each do |candidate|
                label, value = Array(candidate).size > 1 ? candidate : [candidate, candidate]
                option(value: value.to_s, selected: value.to_s == @value.to_s) { label.to_s }
              end
            end
          end
        end
      end
    end
  end
end
