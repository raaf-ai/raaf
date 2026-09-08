# frozen_string_literal: true

module RAAF
  module Rails
    module Ui
      module Atoms
        ##
        # Badge — a pill label.
        #
        # Beyond the palette variants, the badge knows how to colour itself for
        # the two things the dashboard labels constantly: span statuses and
        # span kinds. Those mappings live here so no page has to repeat them.
        #
        # @example Explicit colour
        #   render Atoms::Badge.new("cached", variant: :slate)
        #
        # @example Derived from a span status
        #   render Atoms::Badge.for_status(span.status)
        #
        class Badge < Base
          VARIANTS = %i[
            slate teal green amber red blue glass
            soft-slate soft-teal soft-green soft-amber soft-red soft-blue
            tint-cyan tint-violet tint-green tint-slate
            score-excellent score-good score-fair score-poor score-low
          ].freeze

          # Span statuses as recorded by the tracing processor.
          STATUS_VARIANTS = {
            "ok" => :green,
            "completed" => :green,
            "success" => :green,
            "running" => :blue,
            "pending" => :slate,
            "queued" => :slate,
            "skipped" => :slate,
            "cancelled" => :slate,
            "error" => :red,
            "failed" => :red,
            "timeout" => :amber,
            "degraded" => :amber
          }.freeze

          # Span kinds, so a trace listing reads at a glance.
          KIND_VARIANTS = {
            "agent" => :teal,
            "llm" => :blue,
            "tool" => :green,
            "handoff" => :amber,
            "guardrail" => :red,
            "pipeline" => :slate,
            "response" => :blue
          }.freeze

          # How a score was arrived at, as the eval screens name it. The three
          # methods differ in what a reader can do with the number: a judge's
          # is an opinion, a statistic is a comparison across runs, a rule is
          # arithmetic on the output. "Mixed" is one row's several checks
          # disagreeing about which of those they are.
          CHECK_TYPE_LABELS = {
            "llm_judge" => "LLM judge",
            "statistical" => "Statistical",
            "rule_based" => "Rule-based",
            "mixed" => "Mixed"
          }.freeze

          CHECK_TYPE_VARIANTS = {
            "llm_judge" => :amber,
            "statistical" => :teal,
            "rule_based" => :slate,
            "mixed" => :blue
          }.freeze

          class << self
            # Badge coloured by span status, falling back to a neutral pill.
            def for_status(status, **options)
              new(titleize(status), variant: STATUS_VARIANTS.fetch(status.to_s.downcase, :slate), **options)
            end

            # Badge coloured by span kind.
            def for_kind(kind, **options)
              new(titleize(kind), variant: KIND_VARIANTS.fetch(kind.to_s.downcase, :slate), **options)
            end

            # Badge naming how something was scored.
            #
            # Nil for a type nobody declared, so a screen prints a dash rather
            # than an empty pill: "we were not told" and "a rule did it" are
            # different things, and the fallback the discovery layer applies
            # already makes them hard enough to tell apart.
            def for_check_type(type, **options)
              label = check_type_label(type)
              return nil if label.nil?

              new(label, variant: CHECK_TYPE_VARIANTS.fetch(type.to_s, :slate), **options)
            end

            # @return [String, nil] the human name for a check type
            def check_type_label(type)
              key = type.to_s
              return nil if key.empty? || key == "unknown"

              CHECK_TYPE_LABELS.fetch(key) { titleize(key) }
            end

            private

            # Deliberately not ActiveSupport's `humanize`: the atoms stay
            # loadable outside Rails, and the inputs here are simple keys.
            def titleize(value)
              value.to_s.tr("_-", "  ").split.map(&:capitalize).join(" ")
            end
          end

          # @param label [String, nil]
          # @param variant [Symbol, nil] see VARIANTS
          # @param size [Symbol, nil] :sm
          # @param icon [String, nil] leading Bootstrap Icons name
          # @param mono [Boolean] tabular monospace, for ids and durations
          def initialize(label = nil, variant: :slate, size: nil, icon: nil, mono: false,
                         class: nil, **attrs)
            @label = label
            @variant = variant
            @size = size
            @icon = icon
            @mono = mono
            @class = binding.local_variable_get(:class)
            @attrs = attrs
          end

          def view_template(&block)
            span(class: css, **@attrs) do
              render Icon.new(@icon, size: :sm) if @icon
              slot(@label, &block)
            end
          end

          private

          def css
            tokens(
              "raaf-badge",
              modifier("raaf-badge", @variant, VARIANTS),
              ("raaf-badge--sm" if @size == :sm),
              { "raaf-badge--mono" => @mono },
              @class
            )
          end
        end
      end
    end
  end
end
