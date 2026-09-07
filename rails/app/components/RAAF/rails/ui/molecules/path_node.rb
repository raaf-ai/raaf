# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Molecules
        ##
        # PathNode — one hop on a trace's path.
        #
        # A connector rail with a status dot, then the hop itself: kind chip,
        # name, a note and its duration. The rail's stubs are suppressed at the
        # ends of the list so the line does not float past the first and last
        # nodes.
        #
        # @example
        #   render Molecules::PathNode.new(kind: "tool", name: "crm_upsert",
        #                                  note: "timeout · 2 retries",
        #                                  duration: "4.0s", level: 2, tone: :bad)
        #
        class PathNode < Base
          TONES = %i[ok warn bad idle].freeze

          # @param kind [String]
          # @param name [String]
          # @param note [String, nil] "12 results", "not reached"
          # @param duration [String, nil]
          # @param level [Integer] nesting depth
          # @param tone [Symbol] :ok, :warn, :bad or :idle for a hop not reached
          # @param first [Boolean] suppresses the rail above the dot
          # @param last [Boolean] suppresses the rail below the dot
          # @param href [String, nil]
          def initialize(kind:, name:, note: nil, duration: nil, level: 0, tone: :ok,
                         first: false, last: false, href: nil, class: nil, **attrs)
            @kind = kind
            @name = name
            @note = note
            @duration = duration
            @level = level.to_i
            @tone = tone
            @first = first
            @last = last
            @href = href
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template
            div(class: css, style: "--raaf-tree-level: #{@level}", **@attrs) do
              rail
              if @href
                a(href: @href, class: "raaf-path-body") { contents }
              else
                div(class: "raaf-path-body") { contents }
              end
            end
          end

          private

          def css
            tokens(
              "raaf-path",
              modifier("raaf-path", @tone, TONES),
              { "raaf-path--first" => @first, "raaf-path--last" => @last },
              @class
            )
          end

          def rail
            div(class: "raaf-path-rail") do
              span(class: "raaf-path-stub")
              render Atoms::Dot.new(tone: @tone)
              span(class: "raaf-path-stub")
            end
          end

          def contents
            render Atoms::KindBadge.new(@kind)
            span(class: "raaf-path-name") { @name }
            span(class: "raaf-path-note") { @note } if @note
            render Atoms::Mono.new(@duration, class: "raaf-path-dur") if @duration
          end
        end
      end
    end
  end
end
